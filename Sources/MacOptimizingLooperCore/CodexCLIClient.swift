import Foundation

/// Drives `codex exec` as an alternative to `claude -p`. codex has no `--system` flag,
/// so the system and user prompts are concatenated into the single prompt argument.
/// When the request carries an `outputSchema`, codex's native `--output-schema` returns
/// the final JSON directly (no second formatting pass).
public struct CodexCLIClient: LLMClient {
    private let command: String
    private let environment: [String: String]

    public init(
        command: String = "codex",
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
            throw LLMError.invalidCommand(LLMProviderKind.codex.displayName, String(describing: error))
        }
        guard let executableURL = cliCommand.executableURL(environment: environment) else {
            throw LLMError.missingProviderCLI(LLMProviderKind.codex.displayName)
        }

        let output = try runCodex(request, command: cliCommand, executableURL: executableURL)
        return ChatResponse(choices: [
            ChatResponseChoice(message: ChatMessage(role: "assistant", content: output.trimmingCharacters(in: .whitespacesAndNewlines)))
        ])
    }

    private func runCodex(_ request: ChatRequest, command: CLICommand, executableURL: URL) throws -> String {
        let tmp = FileManager.default.temporaryDirectory
        let token = UUID().uuidString
        // `-o` writes ONLY the final assistant message, so we read clean output instead
        // of scraping it from codex's event-laden stdout.
        let lastMessageURL = tmp.appendingPathComponent("mac-optimizing-looper-codex-\(token).out")
        let schemaURL = tmp.appendingPathComponent("mac-optimizing-looper-codex-\(token).schema.json")
        let errorURL = tmp.appendingPathComponent("mac-optimizing-looper-codex-\(token).err")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: lastMessageURL)
            try? FileManager.default.removeItem(at: schemaURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        if let schema = request.outputSchema {
            try schema.data(using: .utf8)?.write(to: schemaURL, options: .atomic)
        }

        // codex blocks waiting on stdin unless it is closed; route it from /dev/null.
        let nullHandle = FileHandle(forReadingAtPath: "/dev/null")
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? nullHandle?.close()
            try? errorHandle.close()
        }

        let termination = try CLIProcessRunner.run(
            command: command,
            executableURL: executableURL,
            arguments: arguments(for: request, lastMessageURL: lastMessageURL, schemaURL: schemaURL),
            environment: environment,
            standardInput: nullHandle,
            standardOutput: errorHandle,
            standardError: errorHandle
        )

        let errorOutput = String(data: (try? Data(contentsOf: errorURL)) ?? Data(), encoding: .utf8) ?? ""
        guard termination.succeeded else {
            throw LLMError.processFailed(
                termination.status,
                termination.failureMessage(primary: errorOutput)
            )
        }

        let output = String(data: (try? Data(contentsOf: lastMessageURL)) ?? Data(), encoding: .utf8) ?? ""
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.processFailed(0, errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    func arguments(for request: ChatRequest, lastMessageURL: URL, schemaURL: URL) -> [String] {
        var arguments = ["exec", "--skip-git-repo-check", "--sandbox", "read-only"]

        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            arguments.append(contentsOf: ["-m", model])
        }

        let effort = request.effort.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effort.isEmpty {
            arguments.append(contentsOf: ["-c", "model_reasoning_effort=\"\(effort)\""])
        }

        if request.fastMode {
            // Request codex's priority ("Fast") service tier. `service_tier` is the
            // codex config key (verified via `--strict-config`); only set when the
            // caller already confirmed the model supports it (see config validation).
            arguments.append(contentsOf: ["-c", "service_tier=\"priority\""])
        }

        if request.outputSchema != nil {
            arguments.append(contentsOf: ["--output-schema", schemaURL.path])
        }
        arguments.append(contentsOf: ["-o", lastMessageURL.path])

        // codex has no system-prompt flag; fold system into the single prompt argument.
        arguments.append(Self.combinedPrompt(system: request.system, user: request.user))
        return arguments
    }

    static func combinedPrompt(system: String, user: String) -> String {
        let trimmedSystem = system.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSystem.isEmpty else { return user }
        return "\(trimmedSystem)\n\n\(user)"
    }

}
