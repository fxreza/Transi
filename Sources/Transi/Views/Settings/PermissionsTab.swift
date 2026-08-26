import AppKit
import SwiftUI

/// Accessibility and Screen Recording status, each with a Grant/Open System
/// Settings action. Adapted from Klip's `PermissionsView` (its
/// `PermissionRow` + status pill visual pattern), inlined here rather than
/// shared since this tab has no Klip `Theme` fonts to depend on — plain
/// system fonts throughout.
struct PermissionsTab: View {
    @ObservedObject private var permissions = PermissionsState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                accessibilityRow
                screenRecordingRow

                Text("Transi needs no other permissions — network access is only used for translation requests and update checks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(20)
        }
    }

    // MARK: - Accessibility

    private var accessibilityRow: some View {
        PermissionRow(
            icon: "accessibility",
            title: "Accessibility",
            status: permissions.accessibilityTrusted ? .granted : .needed,
            explanation: "Needed to read the selected text from other apps."
        ) {
            if !permissions.accessibilityTrusted {
                HStack(spacing: 8) {
                    Button("Grant…") {
                        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(SystemSettingsPane.accessibility.buttonTitle) {
                        SystemSettingsPane.accessibility.open()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Screen Recording

    private var screenRecordingRow: some View {
        PermissionRow(
            icon: "camera.viewfinder",
            title: "Screen Recording",
            status: permissions.screenRecordingGranted ? .granted : .needed,
            explanation: "Needed for the screenshot-translate hotkey."
        ) {
            if !permissions.screenRecordingGranted {
                HStack(spacing: 8) {
                    Button("Grant…") { ScreenCaptureManager.shared.requestPermissionIfNeeded() }
                        .buttonStyle(.borderedProminent)
                    Button(SystemSettingsPane.screenRecording.buttonTitle) {
                        SystemSettingsPane.screenRecording.open()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

// MARK: - Row

private struct PermissionRow<Actions: View>: View {
    let icon: String
    let title: String
    let status: PermissionRowStatus
    let explanation: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tint)
                    .frame(width: 20)

                Text(title)
                    .font(.body.weight(.semibold))

                Spacer()

                StatusPill(status: status)
            }

            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            actions()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

// MARK: - Status pill

private enum PermissionRowStatus {
    case granted, needed

    var label: String {
        switch self {
        case .granted: return "Granted"
        case .needed: return "Needed"
        }
    }

    var color: Color {
        switch self {
        case .granted: return .green
        case .needed: return .orange
        }
    }
}

private struct StatusPill: View {
    let status: PermissionRowStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(status.color.opacity(0.15)))
            .foregroundStyle(status.color)
    }
}
