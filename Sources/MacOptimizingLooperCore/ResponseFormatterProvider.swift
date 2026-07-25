import Foundation

public protocol ResponseFormatting {
    func format(analysis: String, languageIdentifier: String, model: String) throws -> String
}

public struct ShellResponseFormatterProvider: ResponseFormatting {
    private struct FormatterMetadata: Decodable {
        let jsonPath: String
    }

    private let scriptURL: URL?
    private let claudeCommand: String
    private let environment: [String: String]

    public init(
        scriptURL: URL? = nil,
        claudeCommand: String = "claude",
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.scriptURL = scriptURL
        self.claudeCommand = claudeCommand
        self.environment = environment
    }

    public func format(analysis: String, languageIdentifier: String, model: String) throws -> String {
        guard let scriptURL = scriptURL ?? Self.defaultScriptURL(environment: environment) else {
            throw LLMError.processFailed(-1, "response formatter script not found")
        }
        let command: CLICommand
        do {
            command = try CLICommand(claudeCommand)
        } catch {
            throw LLMError.invalidCommand(LLMProviderKind.claude.displayName, String(describing: error))
        }
        guard let resolvedCommand = command.resolvedComponents(environment: environment) else {
            throw LLMError.missingClaudeCLI
        }

        let fileManager = FileManager.default
        let runDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("mac-optimizing-looper-formatter-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let analysisURL = runDirectory.appendingPathComponent("analysis.txt")
        let outputURL = runDirectory.appendingPathComponent("formatter-metadata.json")
        let errorURL = runDirectory.appendingPathComponent("formatter.stderr.txt")
        try analysis.write(to: analysisURL, atomically: true, encoding: .utf8)
        fileManager.createFile(atPath: outputURL.path, contents: nil)
        fileManager.createFile(atPath: errorURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        var arguments = [
            scriptURL.path,
            "--language", languageIdentifier,
            "--model", model,
            "--analysis-file", analysisURL.path,
            "--output-dir", runDirectory.path
        ]
        for component in resolvedCommand {
            arguments.append(contentsOf: ["--claude-command-arg", component])
        }
        let bashCommand = try CLICommand("/bin/bash")
        let termination = try CLIProcessRunner.run(
            command: bashCommand,
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: arguments,
            environment: environment,
            standardOutput: outputHandle,
            standardError: errorHandle
        )

        let outputData = (try? Data(contentsOf: outputURL)) ?? Data()
        let errorOutput = String(data: (try? Data(contentsOf: errorURL)) ?? Data(), encoding: .utf8) ?? ""
        guard termination.succeeded else {
            throw LLMError.processFailed(
                termination.status,
                termination.failureMessage(primary: errorOutput)
            )
        }

        let metadata = try JSONDecoder().decode(FormatterMetadata.self, from: outputData)
        let jsonURL = URL(fileURLWithPath: metadata.jsonPath)
        return try String(contentsOf: jsonURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func defaultScriptURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let fileManager = FileManager.default
        return scriptCandidates(environment: environment).first { fileManager.isReadableFile(atPath: $0.path) }
    }

    private static func scriptCandidates(environment: [String: String]) -> [URL] {
        var paths: [String] = []
        if let configured = environment["MAC_OPTIMIZING_LOOPER_FORMAT_JSON"], !configured.isEmpty {
            paths.append(configured)
        }
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("mac-optimizing-looper-format-json.sh") {
            paths.append(resourceURL.path)
        }

        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        paths.append(current.appendingPathComponent("script/mac-optimizing-looper-format-json.sh").path)

        var seen = Set<String>()
        return paths.compactMap { path in
            let expanded = (path as NSString).expandingTildeInPath
            guard seen.insert(expanded).inserted else { return nil }
            return URL(fileURLWithPath: expanded)
        }
    }
}
