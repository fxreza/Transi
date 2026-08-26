import SwiftUI

/// Settings tab: one row per `TransiAction`, each with a `HotkeyRecorder`
/// backed by `ShortcutManager`. A successful rebind is pushed straight into
/// `HotkeyManager.shared.rebind(_:to:)` so the new combination is live
/// immediately; a registration failure there shows up as a red caption via
/// `HotkeyRegistration.shared.failureMessages`, independent of the in-window
/// conflict check `ShortcutManager.set(_:for:)` already refused.
struct ShortcutsView: View {
    @ObservedObject private var shortcuts = ShortcutManager.shared
    @ObservedObject private var hotkeyRegistration = HotkeyRegistration.shared

    var body: some View {
        Form {
            Section("Global Shortcuts") {
                ForEach(TransiAction.allCases, id: \.self) { action in
                    ShortcutRow(action: action)
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("Reset All to Defaults") {
                        shortcuts.resetAll()
                        HotkeyManager.shared.applyAll()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One rebindable-or-fixed action row: label, recorder, conflict/failure
/// caption, Reset.
private struct ShortcutRow: View {
    let action: TransiAction
    @ObservedObject private var shortcuts = ShortcutManager.shared
    @ObservedObject private var hotkeyRegistration = HotkeyRegistration.shared
    @State private var conflict: TransiAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(action.label)
                    .foregroundStyle(action.isRebindable ? .primary : .secondary)
                Spacer()
                if isNonDefault {
                    Button("Reset") {
                        shortcuts.reset(action: action)
                        HotkeyManager.shared.rebind(action, to: action.defaultBinding)
                        conflict = nil
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                HotkeyRecorder(
                    display: shortcuts.displayString(for: action),
                    isRebindable: action.isRebindable
                ) { binding in
                    record(binding)
                }
                .frame(width: 120, height: 24)
            }

            if let conflict {
                Text("Already used by \(conflict.label)")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let failure = hotkeyRegistration.failureMessages[action] {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if isNonDefault {
                Button("Reset to Default") {
                    shortcuts.reset(action: action)
                    HotkeyManager.shared.rebind(action, to: action.defaultBinding)
                    conflict = nil
                }
            }
        }
    }

    private var isNonDefault: Bool {
        action.isRebindable && shortcuts.binding(for: action) != action.defaultBinding
    }

    private func record(_ binding: KeyBinding) {
        switch shortcuts.set(binding, for: action) {
        case .ok:
            conflict = nil
            HotkeyManager.shared.rebind(action, to: binding)
        case .conflict(let other):
            conflict = other
        }
    }
}
