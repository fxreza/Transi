import AppKit

/// Tracks the two OS-level permissions the Settings window's Permissions tab
/// reports on — Accessibility (reading the selection) and Screen Recording
/// (the screenshot-translate hotkey) — polling so a grant made in System
/// Settings shows up without a relaunch.
@MainActor
final class PermissionsState: ObservableObject {
    static let shared = PermissionsState()

    @Published private(set) var accessibilityTrusted: Bool = AXIsProcessTrusted()
    @Published private(set) var screenRecordingGranted: Bool = ScreenCaptureManager.shared.hasPermission

    private var timer: Timer?

    private init() {}

    /// Starts a 1 s poll of both permissions. Pair with `stopPolling()`,
    /// driven by whichever window presents the Permissions tab
    /// (`SettingsWindowController`) rather than by view
    /// `onAppear`/`onDisappear`: those fire during any SwiftUI layout pass,
    /// including an offscreen `NSHostingView` render used for verification,
    /// which would start a timer nothing ever tears down.
    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        accessibilityTrusted = AXIsProcessTrusted()
        screenRecordingGranted = ScreenCaptureManager.shared.hasPermission
    }
}
