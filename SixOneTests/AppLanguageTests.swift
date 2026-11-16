//
//  AppLanguageTests.swift
//  SixOneTests

import Foundation
import Testing
@testable import SixOne

@Suite("界面语言解析")
@MainActor
struct AppLanguageTests {
    @Test("Bundle 解析结果映射到受支持的语言，其余回落开发语言")
    func resolvesSupportedLocalizations() {
        #expect(AppLanguage.resolved(from: ["en"]) == .english)
        #expect(AppLanguage.resolved(from: ["zh-Hans"]) == .simplifiedChinese)
        #expect(AppLanguage.resolved(from: ["en", "zh-Hans"]) == .english)
        #expect(AppLanguage.resolved(from: ["zh-Hans", "en"]) == .simplifiedChinese)
        #expect(AppLanguage.resolved(from: ["fr", "zh-Hans"]) == .simplifiedChinese)
        #expect(AppLanguage.resolved(from: ["fr"]) == .english)
        #expect(AppLanguage.resolved(from: []) == .english)
    }

    @Test("应用声明并打包了两种语言")
    func bundlesDeclaredLocalizations() {
        let declared = Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String] ?? []
        #expect(declared.contains("en"))
        #expect(declared.contains("zh-Hans"))
        #expect(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj") != nil)
    }
}
