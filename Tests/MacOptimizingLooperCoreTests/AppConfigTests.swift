import XCTest
@testable import MacOptimizingLooperCore

final class AppConfigTests: XCTestCase {
    func testLoadWithEmptyEnvironmentAndNoFileReturnsDefaults() throws {
        let config = try AppConfig.load(environment: [:], fileContents: nil)

        // Fresh defaults are the "Default" (auto) sentinels, resolved at runtime.
        XCTAssertEqual(config.model, AppConfig.autoSelection)
        XCTAssertEqual(config.thinkingLevel, AppConfig.autoSelection)
        XCTAssertEqual(config.monitorSeconds, 30)
        XCTAssertEqual(config.intervalSeconds, 3_600)
        XCTAssertNil(config.outputLanguageIdentifier)
        XCTAssertEqual(config.terminalAppBundleIdentifier, "com.apple.Terminal")
        XCTAssertFalse(config.resolvedOutputLanguageIdentifier().isEmpty)
        XCTAssertEqual(config.maxTokens, 8192)
        XCTAssertEqual(config.temperature, 0.2)
    }

    func testThinkingLevelLoadsAndClampsInvalidToMax() throws {
        let valid = try AppConfig.load(environment: [:], fileContents: Data(#"{ "thinkingLevel": "high" }"#.utf8))
        XCTAssertEqual(valid.thinkingLevel, "high")

        let invalid = try AppConfig.load(environment: [:], fileContents: Data(#"{ "thinkingLevel": "ultra" }"#.utf8))
        XCTAssertEqual(invalid.thinkingLevel, "max")
    }

    func testMonitorSecondsLoadsAndClampsToRange() throws {
        let valid = try AppConfig.load(environment: [:], fileContents: Data(#"{ "monitorSeconds": 45 }"#.utf8))
        XCTAssertEqual(valid.monitorSeconds, 45)

        let zero = try AppConfig.load(environment: [:], fileContents: Data(#"{ "monitorSeconds": 0 }"#.utf8))
        XCTAssertEqual(zero.monitorSeconds, 0)

        let tooBig = try AppConfig.load(environment: [:], fileContents: Data(#"{ "monitorSeconds": 9999 }"#.utf8))
        XCTAssertEqual(tooBig.monitorSeconds, 600)
    }

    func testMalformedConfigThrows() {
        XCTAssertThrowsError(try AppConfig.load(environment: [:], fileContents: Data("{ not json".utf8))) { error in
            XCTAssertEqual(error as? ConfigError, .malformedFile)
        }
    }

    func testNilFileContentsReturnsDefaults() throws {
        let config = try AppConfig.load(environment: [:], fileContents: nil)

        XCTAssertEqual(config.model, AppConfig.autoSelection)
        XCTAssertEqual(config.intervalSeconds, 3_600)
    }

    func testFileOverridesModelAndClampsInterval() throws {
        let data = try XCTUnwrap("""
        { "model": "custom-model", "intervalSeconds": 10, "outputLanguageIdentifier": "ko-KR" }
        """.data(using: .utf8))

        let config = try AppConfig.load(environment: [:], fileContents: data)

        XCTAssertEqual(config.model, "custom-model")
        XCTAssertEqual(config.intervalSeconds, 60)
        XCTAssertEqual(config.outputLanguageIdentifier, "ko-KR")
    }

    func testFileCanPersistSettingsShape() throws {
        let data = try XCTUnwrap("""
        { "model": "opus", "intervalSeconds": 120, "terminalAppBundleIdentifier": "com.googlecode.iterm2" }
        """.data(using: .utf8))

        let config = try AppConfig.load(environment: [:], fileContents: data)

        XCTAssertEqual(config.model, "opus")
        XCTAssertEqual(config.intervalSeconds, 120)
        XCTAssertEqual(config.terminalAppBundleIdentifier, "com.googlecode.iterm2")
    }

    func testMissingFileUsesMacOSLanguageAsResolvedDefault() throws {
        let config = try AppConfig.load(environment: [:], fileContents: nil)

        XCTAssertNil(config.outputLanguageIdentifier)
        XCTAssertEqual(config.resolvedOutputLanguageIdentifier(), AppConfig.defaultOutputLanguageIdentifier())
    }

    func testSystemOutputLanguageClearsUserOverride() {
        let language = AppConfig.normalizedLanguageIdentifier(
            "system"
        )

        XCTAssertNil(language)
    }

    // MARK: - "Default" (auto) selection

    func testDefaultsAreAutoSelections() throws {
        let config = try AppConfig.load(environment: [:], fileContents: nil)
        XCTAssertTrue(config.isProviderAuto)
        XCTAssertTrue(config.isModelAuto)
        XCTAssertTrue(config.isThinkingAuto)
        XCTAssertEqual(config.resolvedProviderKind, .claude)
    }

    func testAutoSelectionSentinelSurvivesNormalization() {
        XCTAssertEqual(AppConfig.normalizedProvider("default"), AppConfig.autoSelection)
        XCTAssertEqual(AppConfig.normalizedProvider("DEFAULT"), AppConfig.autoSelection)
        XCTAssertEqual(AppConfig.normalizedThinkingLevel("default"), AppConfig.autoSelection)
        XCTAssertEqual(AppConfig.normalizedProvider("codex"), "codex")
        XCTAssertEqual(AppConfig.normalizedProvider("weird"), "claude")
    }

    func testAutoEffortIsOneStepBelowTop() {
        // Claude (…,xhigh,max) → xhigh; codex (…,high,xhigh) → high; order-independent.
        XCTAssertEqual(AppConfig.autoEffort(levels: ["low", "medium", "high", "xhigh", "max"]), "xhigh")
        XCTAssertEqual(AppConfig.autoEffort(levels: ["low", "medium", "high", "xhigh"]), "high")
        XCTAssertEqual(AppConfig.autoEffort(levels: ["xhigh", "max", "low"]), "xhigh")
        XCTAssertEqual(AppConfig.autoEffort(levels: ["max"]), "max")
        XCTAssertEqual(AppConfig.autoEffort(levels: []), "")
    }

    func testResolvedModelAndEffortForAutoConfig() throws {
        let config = try AppConfig.load(environment: [:], fileContents: nil)   // all auto
        let catalog = ClaudeModelCatalog().load()
        XCTAssertEqual(config.resolvedModelSlug(catalog: catalog), "sonnet")
        let levels = catalog.model(slug: "sonnet")?.effortLevels ?? []
        XCTAssertEqual(config.resolvedThinkingLevel(levels: levels), "xhigh")
    }

    func testExplicitPinsOverrideAuto() throws {
        let config = try AppConfig.load(
            environment: [:],
            fileContents: Data(#"{ "model": "opus", "thinkingLevel": "low" }"#.utf8)
        )
        let catalog = ClaudeModelCatalog().load()
        XCTAssertFalse(config.isModelAuto)
        XCTAssertFalse(config.isThinkingAuto)
        XCTAssertEqual(config.resolvedModelSlug(catalog: catalog), "opus")
        XCTAssertEqual(
            config.resolvedThinkingLevel(levels: ["low", "medium", "high", "xhigh", "max"]),
            "low"
        )
    }
}
