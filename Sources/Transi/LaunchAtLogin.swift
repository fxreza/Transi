import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` for the General tab's "Launch
/// at Login" toggle.
///
/// Caveat: `SMAppService` registers whatever bundle is currently running.
/// Under `swift run`/`swift build` there is no signed, installed bundle in
/// `/Applications` for `launchd` to point at, so `register()` throws there —
/// this only behaves correctly against the app `scripts/build-app.sh`
/// installs.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app for launch-at-login, guarded by the
    /// current status so a call that matches the existing state is a no-op
    /// rather than a redundant (and sometimes erroring) API call. Returns an
    /// error message to surface to the user, or `nil` on success.
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return nil }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status != .notRegistered else { return nil }
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
