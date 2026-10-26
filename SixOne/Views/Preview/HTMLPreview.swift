//
//  HTMLPreview.swift
//  SixOne
//
//  HTML 用进程内 WKWebView 预览；本进程持有辅助功能授权，故禁脚本、仅放行本地导航并按类型阻断远程请求。
//

import SwiftUI
import WebKit
import os

private struct HTMLPreview: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // 关闭内容脚本：预览只「看」，不执行页面代码；数据也不落盘。
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.underPageBackgroundColor = .clear
        webView.alphaValue = 0
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.isLoading = $isLoading
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        context.coordinator.load(webView, url: url)
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        var isLoading: Binding<Bool>
        var loadedURL: URL?

        /// 规则编译完成后再加载，避免首次远程请求漏网。
        private static let remoteRuleListIdentifier = "SixOne.HTMLPreview.RemotePolicy"

        /// 只阻断 document/script/raw/popup；图片、样式、字体放行。
        /// 残留风险：远程图片仍会请求并暴露 IP，但拿不到本机内容。见 PRIVACY.md。
        private static let remoteBlockRules = #"""
        [{"trigger":{"url-filter":"^https?://","resource-type":["document","script","raw","popup"]},
          "action":{"type":"block"}}]
        """#

        private var isRemotePolicyInstalled = false
        private let logger = AppLog.logger("HTMLPreview")

        init(isLoading: Binding<Bool>) {
            self.isLoading = isLoading
        }

        func load(_ webView: WKWebView, url: URL) {
            Task { @MainActor in
                await installRemotePolicyIfNeeded(webView)
                // 等规则编译期间可能已切到下一页，别把旧页面载回来。
                guard loadedURL == url else { return }
                // 读取范围给到所在目录，本地相对路径资源才能加载。
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
        }

        private func installRemotePolicyIfNeeded(_ webView: WKWebView) async {
            guard !isRemotePolicyInstalled else { return }
            let list = try? await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: Self.remoteRuleListIdentifier,
                encodedContentRuleList: Self.remoteBlockRules
            )
            if let list {
                webView.configuration.userContentController.add(list)
            } else {
                // 围栏装不上必须出声：静默失效最危险。
                logger.error("远程资源阻断规则编译失败，本次预览未启用该围栏")
            }
            isRemotePolicyInstalled = true
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // 不创建嵌套 WebView，新窗口交给系统浏览器。
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }

            // 用户点击的链接交给系统浏览器；面板内不做前进/返回。
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
                return .cancel
            }

            // 其余只放行本地文件，拦住 meta refresh 等无脚本跳转。
            if url.isFileURL {
                return .allow
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading.wrappedValue = false
            webView.animator().alphaValue = 1
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
            webView.alphaValue = 1
        }
    }
}

struct HTMLPreviewContainer: View {
    let url: URL
    @State private var isLoading = true

    var body: some View {
        ZStack {
            HTMLPreview(url: url, isLoading: $isLoading)
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}
