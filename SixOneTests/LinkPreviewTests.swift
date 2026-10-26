//
//  LinkPreviewTests.swift
//  SixOneTests
//  链接预览底栏取协议+主机+端口；路径/查询/凭据丢弃，非层级 URL 不显示。

import Foundation
import Testing
@testable import SixOne

@Suite("链接预览的协议/主机/端口")
struct LinkPreviewTests {
    @Test("路径、查询与片段都不进底栏")
    func keepsSchemeHostAndPortOnly() {
        #expect(LinkPreview.origin(of: "http://8.135.111.51:3000/explore?schemaVersion=1") == "http://8.135.111.51:3000")
        #expect(LinkPreview.origin(of: "https://example.com/a/b/c?q=1#frag") == "https://example.com")
        #expect(LinkPreview.origin(of: "https://example.com:8443") == "https://example.com:8443")
    }

    @Test("凭据不进底栏：底栏不是复述密码的地方")
    func dropsCredentials() {
        #expect(LinkPreview.origin(of: "https://user:secret@example.com:8443/x") == "https://example.com:8443")
    }

    @Test("非层级 URL 与解析不出来的文本都没有底栏")
    func returnsNilWithoutHost() {
        #expect(LinkPreview.origin(of: "mailto:someone@example.com") == nil)
        #expect(LinkPreview.origin(of: "hello world") == nil)
        #expect(LinkPreview.origin(of: "") == nil)
        #expect(LinkPreview.origin(of: nil) == nil)
    }

    @Test("IPv6 主机带着方括号回来")
    func keepsIPv6Brackets() {
        #expect(LinkPreview.origin(of: "http://[::1]:8080/index.html") == "http://[::1]:8080")
    }

    @Test("中文域名保持原文，不转成 xn-- 写法")
    func keepsNativeScriptHost() {
        #expect(LinkPreview.origin(of: "https://例子.测试/路径") == "https://例子.测试")
    }
}

@Suite("链接预览的打开按钮")
struct LinkPreviewOpenButtonTests {
    @Test("http / https 才认作网页")
    func webSchemes() {
        #expect(PreviewDetailView.isWebScheme("http"))
        #expect(PreviewDetailView.isWebScheme("HTTPS"))
        #expect(!PreviewDetailView.isWebScheme("mailto"))
        #expect(!PreviewDetailView.isWebScheme("ftp"))
        #expect(!PreviewDetailView.isWebScheme(nil))
    }
}
