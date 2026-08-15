import Foundation

/// Optional AI translation via the Claude Code CLI (`claude -p`), billed to the
/// user's Claude subscription — no API key. Only enabled when the CLI is installed.
final class ClaudeAIService {
    static let shared = ClaudeAIService()

    /// Resolved path of the claude CLI, or nil if not installed.
    let claudePath: String? = {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    var isAvailable: Bool { claudePath != nil }

    enum AIError: LocalizedError {
        case notInstalled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Claude CLI not found."
            case .failed(let message): return "AI translation failed: \(message)"
            }
        }
    }

    func translate(_ text: String, to target: TargetLanguage) async throws -> String {
        guard let claudePath else { throw AIError.notInstalled }

        let languageName = target == .persian ? "Persian (Farsi)" : "English"
        let prompt = """
            Translate the following text to \(languageName). \
            Output ONLY the translation, nothing else.

            \(text)
            """

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: claudePath)
                // --tools "" / --setting-sources "" keep this a pure text completion: no
                // tool calls, no CLAUDE.md/project settings discovery. Without them (and
                // with an inherited cwd that may be a TCC-protected folder), headless
                // startup housekeeping can trigger macOS file-access prompts that this
                // non-interactive, no-TTY process can never answer — it just hangs until
                // the timeout below kills it.
                process.arguments = [
                    "-p", prompt, "--output-format", "text",
                    "--tools", "", "--setting-sources", "",
                ]
                process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: AIError.failed(error.localizedDescription))
                    return
                }

                let timeout = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: timeout)

                process.waitUntilExit()
                timeout.cancel()

                let output = String(
                    data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus == 0, !output.isEmpty,
                   !output.lowercased().contains("not logged in") {
                    continuation.resume(returning: output)
                } else {
                    let errorOutput = String(
                        data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
                    )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    // claude prints diagnostics like "Not logged in · Please run /login"
                    // to stdout — surface whichever stream actually has the message.
                    let message = [errorOutput, output]
                        .first { !$0.isEmpty } ?? "exit \(process.terminationStatus)"
                    continuation.resume(throwing: AIError.failed(String(message.prefix(200))))
                }
            }
        }
    }
}
