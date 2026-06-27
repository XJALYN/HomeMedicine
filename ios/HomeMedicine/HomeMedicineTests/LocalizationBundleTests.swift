import XCTest
@testable import HomeMedicine

final class LocalizationBundleTests: XCTestCase {
    func testResolvesSimplifiedChineseFromRegionCode() {
        XCTAssertEqual(LocalizationBundle.resolvedBundleName(for: "zh_CN"), "zh-Hans")
        XCTAssertEqual(LocalizationBundle.resolvedBundleName(for: "zh-Hans_CN"), "zh-Hans")
        XCTAssertEqual(LocalizationBundle.resolvedBundleName(for: "zh-Hans"), "zh-Hans")
    }

    func testResolvesTraditionalChineseFromRegionCode() {
        XCTAssertEqual(LocalizationBundle.resolvedBundleName(for: "zh_TW"), "zh-Hant")
        XCTAssertEqual(LocalizationBundle.resolvedBundleName(for: "zh-Hant_TW"), "zh-Hant")
        XCTAssertEqual(LocalizationBundle.resolvedBundleName(for: "zh-HK"), "zh-Hant")
    }

    func testResolvesEnglishAndPortuguese() {
        XCTAssertEqual(LocalizationBundle.resolvedBundleName(for: "en_US"), "en")
        XCTAssertEqual(LocalizationBundle.resolvedBundleName(for: "pt-BR"), "pt-BR")
        XCTAssertEqual(LocalizationBundle.resolvedBundleName(for: "pt_BR"), "pt-BR")
    }

    func testLocalizedScanTitleUsesChineseBundle() {
        let locale = Locale(identifier: "zh-Hans")
        let title = L10n.t("scan.title", locale: locale)
        XCTAssertEqual(title, "药盒识别")
    }

    func testLocalizedUsageRecordTypeUsesChineseBundle() {
        let locale = Locale(identifier: "zh-Hans")
        XCTAssertEqual(UsageRecordType.stockIn.localizedName(locale: locale), "入库")
        XCTAssertEqual(UsageRecordType.intake.localizedName(locale: locale), "服用")
    }

    func testLocalizedPaywallMembershipUsesChineseBundle() {
        let locale = Locale(identifier: "zh-Hans")
        XCTAssertEqual(L10n.t("paywall.membership", locale: locale), "会员")
        XCTAssertEqual(L10n.t("sharing.title", locale: locale), "家庭共享")
    }

    func testLocalizedFontSizeUsesChineseBundle() {
        let locale = Locale(identifier: "zh-Hans")
        XCTAssertEqual(L10n.t("settings.font_size", locale: locale), "字体大小")
        XCTAssertEqual(L10n.t("settings.font_size.default", locale: locale), "默认")
    }

    func testJapanesePaywallTitleIsTranslated() {
        let locale = Locale(identifier: "ja")
        let title = L10n.t("paywall.title", locale: locale)
        XCTAssertNotEqual(title, "Upgrade")
        XCTAssertFalse(title.isEmpty)
    }

    func testCloudKitSharingErrorUsesLocalizationKey() {
        let locale = Locale(identifier: "zh-Hans")
        let message = CloudKitSharingError.cloudKitNotConfigured.localizedMessage(locale: locale)
        XCTAssertTrue(message.contains("CloudKit"))
        XCTAssertNotEqual(message, "sharing.error.cloudkit_not_configured")
    }
}
