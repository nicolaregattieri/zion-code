import XCTest
import SwiftUI
@testable import Zion

final class DesignSystemTokenTests: XCTestCase {

    // MARK: - Typography Token Inventory

    /// Verify all new bold variant tokens are accessible
    func testBoldVariantTokensExist() {
        let _: Font = DesignSystem.Typography.bodySmallBold
        let _: Font = DesignSystem.Typography.bodyBold
        let _: Font = DesignSystem.Typography.bodyLargeBold
    }

    /// Verify all new semibold variant tokens are accessible
    func testSemiboldVariantTokensExist() {
        let _: Font = DesignSystem.Typography.labelSemibold
        let _: Font = DesignSystem.Typography.bodySemibold
        let _: Font = DesignSystem.Typography.bodySmallSemibold
        let _: Font = DesignSystem.Typography.metaSemibold
    }

    /// Verify all monospaced bold/medium tokens are accessible
    func testMonoVariantTokensExist() {
        let _: Font = DesignSystem.Typography.monoMetaBold
        let _: Font = DesignSystem.Typography.monoSmallBold
        let _: Font = DesignSystem.Typography.monoBodyBold
        let _: Font = DesignSystem.Typography.monoLabelMedium
        let _: Font = DesignSystem.Typography.monoSmallMedium
    }

    /// Verify all large decorative/icon size tokens are accessible
    func testLargeIconTokensExist() {
        let _: Font = DesignSystem.Typography.emptyStateIcon
        let _: Font = DesignSystem.Typography.decorativeIcon
        let _: Font = DesignSystem.Typography.largeIcon
        let _: Font = DesignSystem.Typography.heroIcon
    }

    // MARK: - Existing Token Stability

    /// Verify pre-existing typography tokens are still accessible (regression guard)
    func testExistingTypographyTokensStable() {
        let _: Font = DesignSystem.Typography.screenTitle
        let _: Font = DesignSystem.Typography.sheetTitle
        let _: Font = DesignSystem.Typography.subtitle
        let _: Font = DesignSystem.Typography.sectionTitle
        let _: Font = DesignSystem.Typography.bodyLarge
        let _: Font = DesignSystem.Typography.body
        let _: Font = DesignSystem.Typography.bodySmall
        let _: Font = DesignSystem.Typography.bodyMedium
        let _: Font = DesignSystem.Typography.label
        let _: Font = DesignSystem.Typography.labelMedium
        let _: Font = DesignSystem.Typography.labelBold
        let _: Font = DesignSystem.Typography.meta
        let _: Font = DesignSystem.Typography.metaBold
        let _: Font = DesignSystem.Typography.micro
        let _: Font = DesignSystem.Typography.iconLarge
        let _: Font = DesignSystem.Typography.monoBody
        let _: Font = DesignSystem.Typography.monoSmall
        let _: Font = DesignSystem.Typography.monoLabel
        let _: Font = DesignSystem.Typography.monoLabelBold
        let _: Font = DesignSystem.Typography.monoMeta
    }

    // MARK: - Opacity Token Stability

    func testOpacityTokenValues() {
        XCTAssertEqual(DesignSystem.Opacity.full, 1.0)
        XCTAssertEqual(DesignSystem.Opacity.high, 0.9)
        XCTAssertEqual(DesignSystem.Opacity.visible, 0.7)
        XCTAssertEqual(DesignSystem.Opacity.muted, 0.5)
        XCTAssertEqual(DesignSystem.Opacity.subtle, 0.45)
        XCTAssertEqual(DesignSystem.Opacity.dim, 0.3)
        XCTAssertEqual(DesignSystem.Opacity.faint, 0.15)
        XCTAssertEqual(DesignSystem.Opacity.ghost, 0.08)
    }

    // MARK: - Spacing Token Stability

    func testCornerRadiusTokenValues() {
        XCTAssertEqual(DesignSystem.Spacing.cardCornerRadius, 14)
        XCTAssertEqual(DesignSystem.Spacing.containerCornerRadius, 12)
        XCTAssertEqual(DesignSystem.Spacing.mediumCornerRadius, 10)
        XCTAssertEqual(DesignSystem.Spacing.elementCornerRadius, 8)
        XCTAssertEqual(DesignSystem.Spacing.smallCornerRadius, 6)
        XCTAssertEqual(DesignSystem.Spacing.microCornerRadius, 4)
        XCTAssertEqual(DesignSystem.Spacing.largeCornerRadius, 28)
    }

    // MARK: - IconSize Token Stability

    func testIconSizeTokensExist() {
        let _: Font = DesignSystem.IconSize.sectionHeader
        let _: Font = DesignSystem.IconSize.toolbar
        let _: Font = DesignSystem.IconSize.inline
        let _: Font = DesignSystem.IconSize.meta
        let _: Font = DesignSystem.IconSize.tiny
    }

    // MARK: - Motion Token Stability

    func testMotionTokensExist() {
        let _: Animation = DesignSystem.Motion.springInteractive
        let _: Animation = DesignSystem.Motion.panel
        let _: Animation = DesignSystem.Motion.detail
        let _: Animation = DesignSystem.Motion.snappy
        let _: Animation = DesignSystem.Motion.graph
        let _: Animation = DesignSystem.Motion.glowPulse
    }

    // MARK: - Color Token Stability

    func testSemanticColorTokensExist() {
        let _: Color = DesignSystem.Colors.success
        let _: Color = DesignSystem.Colors.destructive
        let _: Color = DesignSystem.Colors.error
        let _: Color = DesignSystem.Colors.warning
        let _: Color = DesignSystem.Colors.info
        let _: Color = DesignSystem.Colors.background
    }

    // MARK: - Localization Key Balance

    func testLocalizationKeyCountsAreBalanced() {
        let locales = ["en", "pt-BR", "es"]
        var counts: [String: Int] = [:]

        for locale in locales {
            guard let path = Bundle.module.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: locale
            ),
            let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                XCTFail("Could not load Localizable.strings for locale: \(locale)")
                continue
            }
            // Count lines matching `"key" = "value";` pattern
            let keyCount = content.components(separatedBy: .newlines)
                .filter { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return trimmed.hasPrefix("\"") && trimmed.contains("\" = \"")
                }
                .count
            counts[locale] = keyCount
        }

        // All locales should have the same number of keys
        guard let enCount = counts["en"] else { return }
        XCTAssertGreaterThan(enCount, 0, "en locale should have keys")

        for locale in locales where locale != "en" {
            XCTAssertEqual(
                counts[locale], enCount,
                "\(locale) has \(counts[locale] ?? 0) keys but en has \(enCount) — locales are out of sync"
            )
        }
    }
}
