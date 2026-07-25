import Foundation

public enum CLICommandError: Error, Equatable, CustomStringConvertible {
    case empty
    case trailingEscape
    case unterminatedQuote

    public var description: String {
        switch self {
        case .empty: return "command is empty"
        case .trailingEscape: return "command ends with an escape character"
        case .unterminatedQuote: return "command has an unterminated quote"
        }
    }
}

/// A user-configured executable plus fixed prefix arguments. This is intentionally
/// argv-only: shell operators are passed as ordinary arguments, so a command such as
/// `ag claude agp` can wrap the native CLI without introducing `eval` or shell injection.
public struct CLICommand: Equatable, Sendable {
    public let components: [String]

    public init(_ rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CLICommandError.empty }
        let components = try Self.parse(trimmed)
        guard !components.isEmpty else { throw CLICommandError.empty }
        self.components = components
    }

    public func executableURL(environment: [String: String]) -> URL? {
        let executable = (components[0] as NSString).expandingTildeInPath
        let fileManager = FileManager.default

        if executable.contains("/") {
            let url = URL(fileURLWithPath: executable)
            return fileManager.isExecutableFile(atPath: url.path) ? url : nil
        }

        let path = Self.processEnvironment(from: environment)["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let url = URL(fileURLWithPath: String(directory)).appendingPathComponent(executable)
            if fileManager.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    public func resolvedComponents(environment: [String: String]) -> [String]? {
        guard let executableURL = executableURL(environment: environment) else { return nil }
        return [executableURL.path] + components.dropFirst()
    }

    public static func processEnvironment(from environment: [String: String]) -> [String: String] {
        var result = environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fallbackPath = "\(home)/.bun/bin:\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPath = result["PATH"], !currentPath.isEmpty {
            result["PATH"] = "\(currentPath):\(fallbackPath)"
        } else {
            result["PATH"] = fallbackPath
        }
        return result
    }

    private static func parse(_ value: String) throws -> [String] {
        enum Quote { case none, single, double }

        var quote = Quote.none
        var escaping = false
        var tokenStarted = false
        var token = ""
        var result: [String] = []

        func appendToken() {
            guard tokenStarted else { return }
            result.append(token)
            token = ""
            tokenStarted = false
        }

        for character in value {
            if escaping {
                token.append(character)
                tokenStarted = true
                escaping = false
                continue
            }

            switch quote {
            case .none:
                if character == "\\" {
                    escaping = true
                    tokenStarted = true
                } else if character == "'" {
                    quote = .single
                    tokenStarted = true
                } else if character == "\"" {
                    quote = .double
                    tokenStarted = true
                } else if character.isWhitespace {
                    appendToken()
                } else {
                    token.append(character)
                    tokenStarted = true
                }
            case .single:
                if character == "'" {
                    quote = .none
                } else {
                    token.append(character)
                }
            case .double:
                if character == "\"" {
                    quote = .none
                } else if character == "\\" {
                    escaping = true
                } else {
                    token.append(character)
                }
            }
        }

        guard !escaping else { throw CLICommandError.trailingEscape }
        guard quote == .none else { throw CLICommandError.unterminatedQuote }
        appendToken()
        return result
    }
}

struct CLIProcessTermination {
    let status: Int32
    let reason: Process.TerminationReason

    var succeeded: Bool { reason == .exit && status == 0 }

    func failureMessage(primary: String, fallback: String = "") -> String {
        let output = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = output.isEmpty ? fallback : output
        guard reason == .uncaughtSignal else { return detail }
        return detail.isEmpty ? "terminated by signal \(status)" : "terminated by signal \(status): \(detail)"
    }
}

enum CLIProcessRunner {
    static func run(
        command: CLICommand,
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        standardInput: Any? = nil,
        standardOutput: Any? = nil,
        standardError: Any? = nil
    ) throws -> CLIProcessTermination {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = Array(command.components.dropFirst()) + arguments
        process.environment = CLICommand.processEnvironment(from: environment)
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        // No timeout by design. `waitUntilExit` returns on the CLI's real exit and exposes
        // both normal exit codes and signal termination; wrappers such as `ag` use `exec`,
        // so their child CLI's termination is preserved here.
        process.waitUntilExit()
        return CLIProcessTermination(status: process.terminationStatus, reason: process.terminationReason)
    }
}
