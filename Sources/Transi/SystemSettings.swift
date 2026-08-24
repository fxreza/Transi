import AppKit

/// Deep links into the Privacy & Security panes Transi needs, so a
/// permission error can put the user in the right place instead of describing
/// where to click.
enum SystemSettingsPane: String {
    case accessibility = "Privacy_Accessibility"
    case screenRecording = "Privacy_ScreenCapture"

    /// Label for the button that opens this pane.
    var buttonTitle: String {
        switch self {
        case .accessibility: return "Open Accessibility Settings"
        case .screenRecording: return "Open Screen Recording Settings"
        }
    }

    func open() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")!
        NSWorkspace.shared.open(url)
    }
}
