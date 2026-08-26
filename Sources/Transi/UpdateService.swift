import Foundation
import AppKit

/// Checks GitHub Releases for newer builds of Transi and installs them.
///
/// Ported from Klip's `UpdateService` (Services/UpdateService.swift). The
/// progress window, success toast, and in-app changelog were dropped —
/// downloads happen silently and the app just relaunches when the swap is
/// done. The signing-identity check was also loosened: GitHub release zips
/// for this app are not expected to always carry the exact same signing
/// authority as the locally-signed running copy (see `identityValidForInstall`
/// below), so a mismatch there asks the user instead of refusing outright.
class UpdateService {
    static let shared = UpdateService()
    private init() {}

    private let releasesURL = URL(string: "https://api.github.com/repos/fxreza/Transi/releases")!
    private let lastCheckKey = "lastUpdateCheckDate"
    private let repoBaseURL = "https://github.com/fxreza/Transi"

    func checkOnLaunchIfNeeded() {
        if let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < 86400 {
            let hoursAgo = Date().timeIntervalSince(lastCheck) / 3600
            print("[UpdateService] Skipping launch check — last checked \(String(format: "%.1f", hoursAgo))h ago")
            return
        }
        print("[UpdateService] Running launch check")
        checkForUpdates(silent: true)
    }

    func checkForUpdates(silent: Bool) {
        print("[UpdateService] checkForUpdates(silent: \(silent))")
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                print("[UpdateService] Network error: \(error.localizedDescription)")
                if !silent { self?.showCheckFailedAlert() }
                return
            }
            if let http = response as? HTTPURLResponse {
                print("[UpdateService] GitHub API responded: HTTP \(http.statusCode)")
            }
            guard let self,
                  let data,
                  let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                print("[UpdateService] Failed to parse releases JSON")
                if !silent { self?.showCheckFailedAlert() }
                return
            }
            print("[UpdateService] Fetched \(releases.count) release(s)")
            self.handleReleases(releases, silent: silent)
        }.resume()
    }

    private func handleReleases(_ releases: [[String: Any]], silent: Bool) {
        let includePrereleases = UserDefaults.standard.bool(forKey: "includePrereleases")
        let sorted = releases
            .filter { includePrereleases || ($0["prerelease"] as? Bool) != true }
            .sorted { (($0["published_at"] as? String) ?? "") > (($1["published_at"] as? String) ?? "") }

        #if arch(arm64)
        let archKeyword = "Silicon"
        #else
        let archKeyword = "Intel"
        #endif

        var latestTag: String?
        var latestZipURL: String?
        for release in sorted {
            guard let tag = release["tag_name"] as? String,
                  let assets = release["assets"] as? [[String: Any]] else { continue }
            let archZip = assets.first(where: {
                guard let name = $0["name"] as? String else { return false }
                return name.hasSuffix(".zip") && name.contains(archKeyword)
            })
            let anyZip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true })
            if let zip = archZip ?? anyZip,
               let url = zip["browser_download_url"] as? String {
                latestTag = tag
                latestZipURL = url
                print("[UpdateService] Selected asset: \(zip["name"] as? String ?? "?") (\(archKeyword) preferred)")
                break
            }
        }

        guard let tag = latestTag, let zipURL = latestZipURL else {
            print("[UpdateService] No release with a .zip asset found")
            if !silent { DispatchQueue.main.async { self.showCheckFailedAlert() } }
            return
        }

        let latest = stripTagPrefix(tag)
        let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        print("[UpdateService] Latest: \(latest)  Current: \(current)  ZipURL: \(zipURL)")

        DispatchQueue.main.async {
            if self.versionIsNewer(latest, than: current) {
                print("[UpdateService] Update available — showing alert")
                self.showUpdateAlert(version: latest, tag: tag, downloadURL: zipURL)
            } else {
                print("[UpdateService] Already up to date (silent: \(silent))")
                if !silent { self.showUpToDateAlert() }
            }
        }
    }

    private func stripTagPrefix(_ tag: String) -> String {
        var v = tag
        let lower = v.lowercased()
        if lower.hasPrefix("transi-v") {
            v = String(v.dropFirst("transi-v".count))
        } else if lower.hasPrefix("v") {
            v = String(v.dropFirst(1))
        }
        return v
    }

    private func versionIsNewer(_ latest: String, than current: String) -> Bool {
        let lp = latest.split(separator: ".").compactMap { Int($0) }
        let cp = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(lp.count, cp.count) {
            let l = i < lp.count ? lp[i] : 0
            let c = i < cp.count ? cp[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }

    private func showUpdateAlert(version: String, tag: String, downloadURL: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Transi \(version) is available"
        alert.informativeText = "A new version of Transi is ready to download and install."
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        print("[UpdateService] Update alert response: \(response == .alertFirstButtonReturn ? "Update Now" : "Later")")
        if response == .alertFirstButtonReturn {
            downloadAndInstall(url: downloadURL, tag: tag)
        }
    }

    private func showUpToDateAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "You're up to date"
        alert.informativeText = "Transi is already on the latest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Shown for a manual (non-silent) check that failed to reach GitHub or
    /// parse its response. The donor only logged this case; a check the user
    /// asked for directly should tell them it failed rather than going quiet.
    private func showCheckFailedAlert() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.icon = NSApp.applicationIconImage
            alert.messageText = "Could Not Check for Updates"
            alert.informativeText = "Transi could not reach GitHub to check for updates. Check your network connection and try again."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func downloadAndInstall(url: String, tag: String) {
        guard let downloadURL = URL(string: url) else {
            print("[UpdateService] Invalid download URL: \(url)")
            return
        }
        print("[UpdateService] Starting download: \(url)")
        // No progress window — the download and install happen silently.
        // Failures still surface via the alerts below.

        URLSession.shared.downloadTask(with: downloadURL) { [weak self] localURL, _, error in
            guard let self else { return }

            func fail(_ reason: String) {
                print("[UpdateService] \(reason)")
            }

            if let error {
                return fail("Download error: \(error.localizedDescription)")
            }
            guard let localURL else {
                return fail("Download returned no file")
            }
            print("[UpdateService] Download complete: \(localURL.path)")

            // 1. UUID-based temp dir — not guessable by other processes
            let fm = FileManager.default
            let tmpBase = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("TransiUpdate_\(UUID().uuidString)")
            let zipURL    = tmpBase.appendingPathComponent("update.zip")
            let extractURL = tmpBase.appendingPathComponent("extracted")
            let newAppURL  = extractURL.appendingPathComponent("Transi.app")
            let scriptURL  = tmpBase.appendingPathComponent("install.sh")

            do {
                try fm.createDirectory(at: tmpBase, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                try fm.moveItem(at: localURL, to: zipURL)
                print("[UpdateService] Zip at: \(zipURL.path)")
            } catch {
                return fail("Failed to prepare temp dir: \(error)")
            }

            // Sanity-check the payload before handing it to ditto: an error
            // page or a truncated download is not worth extracting.
            let zipSize = ((try? fm.attributesOfItem(atPath: zipURL.path))?[.size] as? NSNumber)?.intValue ?? 0
            guard zipSize > 100_000, zipSize < 500_000_000 else {
                return fail("Downloaded asset has an implausible size (\(zipSize) bytes)")
            }

            // 2. Extract zip in Swift so we can inspect it before touching /Applications
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-xk", zipURL.path, extractURL.path]
            do {
                try ditto.run(); ditto.waitUntilExit()
                guard ditto.terminationStatus == 0 else {
                    return fail("ditto extraction failed (exit \(ditto.terminationStatus))")
                }
                print("[UpdateService] Extraction OK")
            } catch {
                return fail("Failed to run ditto: \(error)")
            }

            // 3. Confirm Transi.app is actually present after extraction
            guard fm.fileExists(atPath: newAppURL.path) else {
                return fail("Transi.app not found in extracted zip at \(newAppURL.path)")
            }

            // 4. Verify the signature is internally consistent before
            //    replacing anything. This alone cannot tell a genuine Transi
            //    build from any other signed bundle at the download URL —
            //    that is what the bundle-identifier + identity check below is
            //    for.
            let codesign = Process()
            codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            codesign.arguments = ["--verify", "--strict", newAppURL.path]
            do {
                try codesign.run(); codesign.waitUntilExit()
                guard codesign.terminationStatus == 0 else {
                    return fail("Code signature verification failed (exit \(codesign.terminationStatus))")
                }
                print("[UpdateService] Code signature verified OK")
            } catch {
                return fail("Failed to run codesign: \(error)")
            }

            // 4b. The downloaded bundle must identify itself as Transi. If it
            //     also carries a different signing authority than the
            //     running app — expected for a build downloaded fresh from a
            //     GitHub release, since the release zip is not signed with
            //     this Mac's local "Transi Dev" identity — ask before
            //     installing instead of refusing outright.
            guard let candidate = Self.signingInfo(at: newAppURL.path) else {
                Self.showIdentityRefusedAlert(reason: "the downloaded app's signature could not be read")
                return fail("Could not read the downloaded bundle's signing info")
            }
            guard let running = Self.signingInfo(at: Bundle.main.bundlePath) else {
                Self.showIdentityRefusedAlert(reason: "this app's own signature could not be read")
                return fail("Could not read the running bundle's signing info")
            }
            let verdict = Self.identityValidForInstall(candidate: candidate, running: running)
            guard verdict.allowed else {
                let reason = verdict.reason ?? "its signing identity could not be validated"
                Self.showIdentityRefusedAlert(reason: reason)
                return fail("Refusing to install: \(reason)")
            }
            if verdict.needsConfirmation {
                var userConfirmed = false
                DispatchQueue.main.sync {
                    userConfirmed = Self.confirmDifferentIdentityInstall(reason: verdict.reason ?? "")
                }
                guard userConfirmed else {
                    return fail("User declined install after signing-identity mismatch")
                }
            }
            print("[UpdateService] Signing identity check passed (needsConfirmation: \(verdict.needsConfirmation))")

            // 5. Write install script — extraction already done, the script
            //    only stages, swaps and opens. Paths are passed as positional
            //    arguments rather than interpolated into the script text.
            let script = Self.installScript()
            do {
                try script.write(to: scriptURL, atomically: true, encoding: .utf8)
                print("[UpdateService] Install script written to: \(scriptURL.path)")
            } catch {
                return fail("Failed to write install script: \(error)")
            }

            // 6. chmod 755
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["755", scriptURL.path]
            do {
                try chmod.run(); chmod.waitUntilExit()
            } catch {
                return fail("Failed to chmod script: \(error)")
            }

            // 7. Launch script detached via nohup so it survives the app
            //    quitting. `sh -c '…' arg0 arg1 arg2` binds $0/$1/$2, so no
            //    path is ever interpolated into shell text.
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
            launcher.arguments = [
                "-c",
                "nohup /bin/bash \"$0\" \"$1\" \"$2\" >/dev/null 2>&1 &",
                scriptURL.path,
                newAppURL.path,
                Self.installDestination,
            ]
            do {
                try launcher.run()
                launcher.waitUntilExit() // wait for fork to complete before we exit
                print("[UpdateService] Install script detached, terminating app")
            } catch {
                return fail("Failed to launch install script: \(error)")
            }

            UserDefaults.standard.set(Date(), forKey: self.lastCheckKey) // suppress launch check in new app
            UserDefaults.standard.synchronize() // flush to disk before process exits

            DispatchQueue.main.async {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }.resume()
    }

    // MARK: - Install script

    /// Where an update is installed.
    static let installDestination = "/Applications/Transi.app"

    /// The bundle identifier an update must carry to be installed.
    static let expectedBundleIdentifier = "com.fxreza.transi"

    /// The installer, as a standalone bash script.
    ///
    /// Arguments: `$1` = the extracted new bundle, `$2` = the destination.
    /// `$3`/`$4` exist only so a test can run this for real without waiting
    /// two seconds and without launching anything; the app passes neither, so
    /// production behaviour is the defaults.
    ///
    /// Stages the new bundle next to the destination first, moves the old one
    /// aside, swaps, and only then deletes the old copy — restoring it if any
    /// step fails, rather than deleting the old app before the copy is known
    /// to have succeeded. Every path is quoted.
    static func installScript() -> String {
        """
        #!/bin/bash
        # Transi updater. $1 = new bundle, $2 = destination,
        # $3 = seconds to wait first (default 2), $4 = relaunch? 1/0 (default 1).
        set -u

        NEW_APP="$1"
        TARGET="$2"
        WAIT="${3:-2}"
        RELAUNCH="${4:-1}"
        STAGE="${TARGET}.new"
        OLD="${TARGET}.old"

        fail() {
            osascript -e "display alert \\"Transi Update Failed\\" message \\"$1 Try updating manually.\\"" >/dev/null 2>&1
            exit 1
        }

        sleep "$WAIT"

        # Stage beside the destination, on the same volume, so the swap below
        # is an atomic rename rather than a copy.
        rm -rf "$STAGE"
        if ! cp -R "$NEW_APP" "$STAGE"; then
            rm -rf "$STAGE"
            fail "Could not stage the new app."
        fi
        xattr -cr "$STAGE" >/dev/null 2>&1

        rm -rf "$OLD"
        if [ -e "$TARGET" ]; then
            if ! mv "$TARGET" "$OLD"; then
                rm -rf "$STAGE"
                fail "Could not move the old app aside."
            fi
        fi

        if ! mv "$STAGE" "$TARGET"; then
            # Put the old app back before giving up.
            if [ -e "$OLD" ]; then mv "$OLD" "$TARGET"; fi
            rm -rf "$STAGE"
            fail "Could not install the new app."
        fi

        rm -rf "$OLD"

        if [ "$RELAUNCH" = "1" ]; then
            sleep 1
            /bin/launchctl asuser $(id -u) /usr/bin/open "$TARGET"
        fi
        """
    }

    // MARK: - Signing identity

    /// What `codesign -dvv` reports about a bundle.
    struct SigningInfo: Equatable {
        var identifier: String?
        /// The `Authority=` chain, leaf first. Empty for an ad-hoc signature.
        var authorities: [String]
    }

    /// Parses `codesign -dvv` output (which goes to stderr).
    static func parseSigningInfo(_ output: String) -> SigningInfo {
        var identifier: String?
        var authorities: [String] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Identifier="), identifier == nil {
                identifier = String(trimmed.dropFirst("Identifier=".count))
            } else if trimmed.hasPrefix("Authority=") {
                authorities.append(String(trimmed.dropFirst("Authority=".count)))
            }
        }
        return SigningInfo(identifier: identifier, authorities: authorities)
    }

    /// Whether `candidate` may be installed over `running`, and whether the
    /// user should confirm first.
    ///
    /// The bundle identifier is a hard requirement — a downloaded bundle that
    /// does not identify itself as Transi is never installed. The signing
    /// authority chain is not: distribution builds published from GitHub
    /// Actions (or any machine other than the one that built the running
    /// copy) are legitimately signed by a different identity than a
    /// locally-built copy signed with this Mac's own "Transi Dev" identity.
    /// Klip's stricter version of this check treated any such difference as
    /// a refusal; here it is instead surfaced to the user as a confirmation,
    /// since it is the expected case for this app rather than a sign of
    /// tampering.
    static func identityValidForInstall(
        candidate: SigningInfo,
        running: SigningInfo
    ) -> (allowed: Bool, needsConfirmation: Bool, reason: String?) {
        guard candidate.identifier == expectedBundleIdentifier else {
            return (
                false,
                false,
                "the downloaded app identifies itself as \"\(candidate.identifier ?? "nothing")\", not \(expectedBundleIdentifier)"
            )
        }
        if candidate.authorities == running.authorities {
            return (true, false, nil)
        }
        let signer = candidate.authorities.first ?? "no signing authority"
        let expected = running.authorities.first ?? "no signing authority"
        return (
            true,
            true,
            "the downloaded app is signed by \(signer), but this copy of Transi is signed by \(expected)"
        )
    }

    /// Reads a bundle's signing info via `codesign -dvv`.
    static func signingInfo(at path: String) -> SigningInfo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dvv", path]
        let pipe = Pipe()
        // codesign writes its display output to stderr.
        process.standardError = pipe
        process.standardOutput = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return parseSigningInfo(String(decoding: data, as: UTF8.self))
        } catch {
            print("[UpdateService] Failed to run codesign -dvv: \(error)")
            return nil
        }
    }

    /// Shown when the downloaded bundle fails the hard requirement (wrong
    /// bundle identifier, or its signature could not be read at all).
    /// Installation is never allowed to proceed past this alert.
    private static func showIdentityRefusedAlert(reason: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.icon = NSApp.applicationIconImage
            alert.messageText = "Update Refused"
            alert.informativeText = """
            Transi did not install this update because \(reason).

            Nothing has been changed. Download the update yourself from \
            github.com/fxreza/Transi/releases if you were expecting one.
            """
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Shown when the downloaded bundle passes every hard requirement but
    /// carries a different signing authority than the running app. Must be
    /// called on the main thread; blocks until the user answers.
    private static func confirmDifferentIdentityInstall(reason: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Different Signing Identity"
        alert.informativeText = """
        This update is signed by a different identity than your installed copy \
        (expected for GitHub releases). Install anyway?

        (\(reason).)

        Because the signing identity is changing, macOS may ask you to \
        re-grant Accessibility/Screen Recording permissions after this update \
        installs — TCC grants follow the signing identity.
        """
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
