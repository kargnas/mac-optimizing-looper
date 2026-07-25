import Foundation

public struct ClaudeCLIClient: LLMClient {
    private let command: String
    private let environment: [String: String]

    public init(
        command: String = "claude",
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.command = command
        self.environment = environment
    }

    public func complete(_ request: ChatRequest) async throws -> ChatResponse {
        let cliCommand: CLICommand
        do {
            cliCommand = try CLICommand(command)
        } catch {
            throw LLMError.invalidCommand(LLMProviderKind.claude.displayName, String(describing: error))
        }
        guard let executableURL = cliCommand.executableURL(environment: environment) else {
            throw LLMError.missingClaudeCLI
        }

        let output = try runClaude(request, command: cliCommand, executableURL: executableURL)
        return ChatResponse(choices: [
            ChatResponseChoice(message: ChatMessage(role: "assistant", content: output.trimmingCharacters(in: .whitespacesAndNewlines)))
        ])
    }

    private func runClaude(_ request: ChatRequest, command: CLICommand, executableURL: URL) throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-optimizing-looper-claude-\(UUID().uuidString).out")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-optimizing-looper-claude-\(UUID().uuidString).err")
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-optimizing-looper-claude-\(UUID().uuidString).in")
        try request.user.data(using: .utf8)?.write(to: inputURL, options: .atomic)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
            try? FileManager.default.removeItem(at: inputURL)
        }

        let inputHandle = try FileHandle(forReadingFrom: inputURL)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? inputHandle.close()
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let termination = try CLIProcessRunner.run(
            command: command,
            executableURL: executableURL,
            arguments: arguments(for: request),
            environment: environment,
            standardInput: inputHandle,
            standardOutput: outputHandle,
            standardError: errorHandle
        )

        let output = String(data: (try? Data(contentsOf: outputURL)) ?? Data(), encoding: .utf8) ?? ""
        let errorOutput = String(data: (try? Data(contentsOf: errorURL)) ?? Data(), encoding: .utf8) ?? ""

        guard termination.succeeded else {
            // claude prints API failures ("API Error: 429 …", usage-limit notices) to
            // STDOUT and exits nonzero with an EMPTY stderr, so stderr alone loses the
            // actual cause and the UI shows a bare "process failed 1". Fall back to
            // stdout (capped: it is unbounded and lands in a one-line menu title).
            let stderrText = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdoutText = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = String(stdoutText.prefix(300))
            throw LLMError.processFailed(
                termination.status,
                termination.failureMessage(primary: stderrText, fallback: fallback)
            )
        }

        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidResponse
        }
        return output
    }

    private func arguments(for request: ChatRequest) -> [String] {
        let effort = request.effort.trimmingCharacters(in: .whitespacesAndNewlines)
        var arguments = [
            "-p",
            "--no-session-persistence",
            // We run claude headless from a background app, so there is no TTY to answer
            // an interactive permission prompt. `plan` is read-only: claude may run
            // read-only inspections (verified: `ps`; likewise df/du/vm_stat for capacity)
            // to investigate, but writes/edits are categorically blocked by the mode —
            // independent of how any individual command would be classified. This still
            // lets claude RECOMMEND a fix command as inert text; the app (not claude) runs
            // it later on the user's click. For a kernel-enforced guarantee an OS sandbox
            // could wrap this process; codex already runs under `--sandbox read-only`.
            "--permission-mode", "plan",
            "--output-format", "text",
            "--effort", effort.isEmpty ? "low" : effort,
            "--system-prompt", request.system
        ]
        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        return arguments
    }

}
