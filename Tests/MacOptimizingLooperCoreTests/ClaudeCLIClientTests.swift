import XCTest
@testable import MacOptimizingLooperCore

final class ClaudeCLIClientTests: XCTestCase {
    private func makeFakeCLI(script: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-optimizing-looper-fake-claude-\(UUID().uuidString).sh")
        try "#!/bin/bash\n\(script)".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func request() -> ChatRequest {
        ChatRequest(model: "fable", system: "sys", user: "user", maxTokens: 100, temperature: 0, effort: "low")
    }

    /// claude prints API failures (e.g. "API Error: 429 …") to STDOUT and exits 1 with an
    /// empty stderr. The error surfaced to the UI must carry that stdout text, otherwise
    /// the menu shows a bare "process failed 1" with no cause.
    func testFailureWithEmptyStderrFallsBackToStdout() async throws {
        let cli = try makeFakeCLI(script: "cat >/dev/null\necho 'API Error: 429 usage limit reached'\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: cli) }

        let client = ClaudeCLIClient(command: cli.path, environment: [:])
        do {
            _ = try await client.complete(request())
            XCTFail("expected processFailed")
        } catch let LLMError.processFailed(status, message) {
            XCTAssertEqual(status, 1)
            XCTAssertEqual(message, "API Error: 429 usage limit reached")
        }
    }

    /// When stderr does have content it stays the primary error source (existing behavior).
    func testFailureWithStderrKeepsStderrMessage() async throws {
        let cli = try makeFakeCLI(script: "cat >/dev/null\necho 'partial stdout'\necho 'real error' >&2\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: cli) }

        let client = ClaudeCLIClient(command: cli.path, environment: [:])
        do {
            _ = try await client.complete(request())
            XCTFail("expected processFailed")
        } catch let LLMError.processFailed(status, message) {
            XCTAssertEqual(status, 1)
            XCTAssertEqual(message, "real error")
        }
    }

    /// Successful runs must be unaffected by the stdout-fallback change.
    func testSuccessReturnsStdout() async throws {
        let cli = try makeFakeCLI(script: "cat >/dev/null\necho 'analysis notes'\n")
        defer { try? FileManager.default.removeItem(at: cli) }

        let client = ClaudeCLIClient(command: cli.path, environment: [:])
        let response = try await client.complete(request())
        XCTAssertEqual(response.choices.first?.message.content, "analysis notes")
    }

    func testCustomCommandPrefixRunsBeforeNativeArguments() async throws {
        let cli = try makeFakeCLI(script: "test \"$1\" = route || exit 9\ncat >/dev/null\necho 'wrapped analysis'\n")
        defer { try? FileManager.default.removeItem(at: cli) }

        let client = ClaudeCLIClient(command: "\(cli.path) route", environment: [:])
        let response = try await client.complete(request())
        XCTAssertEqual(response.choices.first?.message.content, "wrapped analysis")
    }

    func testSignalTerminationIsReportedInsteadOfHanging() async throws {
        let cli = try makeFakeCLI(script: "kill -TERM $$\n")
        defer { try? FileManager.default.removeItem(at: cli) }

        let client = ClaudeCLIClient(command: cli.path, environment: [:])
        do {
            _ = try await client.complete(request())
            XCTFail("expected processFailed")
        } catch let LLMError.processFailed(status, message) {
            XCTAssertEqual(status, 15)
            XCTAssertTrue(message.contains("terminated by signal 15"))
        }
    }

    func testFormatterUsesCustomClaudeCommandPrefix() throws {
        let cli = try makeFakeCLI(script: "test \"$1\" = route || exit 9\necho '{\"summary\":\"ok\",\"statusBar\":{\"title\":\"0\",\"color\":\"green\"},\"suggestions\":[]}'\n")
        defer { try? FileManager.default.removeItem(at: cli) }
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("script/mac-optimizing-looper-format-json.sh")
        let formatter = ShellResponseFormatterProvider(
            scriptURL: scriptURL,
            claudeCommand: "\(cli.path) route",
            environment: [:]
        )

        let output = try formatter.format(analysis: "notes", languageIdentifier: "en", model: "sonnet")
        XCTAssertTrue(output.contains("\"summary\": \"ok\""))
    }
}
