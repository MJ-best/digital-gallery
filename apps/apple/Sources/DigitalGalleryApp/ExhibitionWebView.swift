import GalleryBridge
import SwiftUI
import WebKit

/// Controller that bridges SwiftUI edits straight into `window.__galleryBridge`
/// inside `WKWebView` without reloading the page or resetting scroll position.
@MainActor
final class WebPreviewController {
    weak var webView: WKWebView?

    func scrollToScene(_ sceneID: String) {
        let escaped = jsString(sceneID)
        webView?.evaluateJavaScript("window.__galleryBridge?.scrollToScene(\(escaped));", completionHandler: nil)
    }

    func patchAtmosphere(sceneID: String, palette: FfiPalette) {
        let payload: [String: String] = [
            "background": palette.background,
            "surface": palette.surface,
            "foreground": palette.foreground,
            "muted": palette.muted,
            "accent": palette.accent,
            "border": palette.border,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
        let escapedID = jsString(sceneID)
        webView?.evaluateJavaScript(
            "window.__galleryBridge?.patchSceneAtmosphere(\(escapedID), \(json), \(palette.vignette));",
            completionHandler: nil
        )
    }

    func patchText(sceneID: String, title: String, chapter: String, note: String, caption: String) {
        let payload: [String: String] = [
            "title": title,
            "chapter": chapter,
            "note": note,
            "caption": caption,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
        let escapedID = jsString(sceneID)
        webView?.evaluateJavaScript(
            "window.__galleryBridge?.patchSceneText(\(escapedID), \(json));",
            completionHandler: nil
        )
    }

    func patchItem(sceneID: String, index: UInt32, title: String?, caption: String?) {
        var payload: [String: String] = [:]
        if let title { payload["title"] = title }
        if let caption { payload["caption"] = caption }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
        let escapedID = jsString(sceneID)
        webView?.evaluateJavaScript(
            "window.__galleryBridge?.patchSceneItem(\(escapedID), \(index), \(json));",
            completionHandler: nil
        )
    }

    func patchTheme(_ themePreset: String) {
        let escaped = jsString(themePreset)
        webView?.evaluateJavaScript(
            "window.__galleryBridge?.patchTheme(\(escaped));",
            completionHandler: nil
        )
    }

    private func jsString(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s),
              let encoded = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return encoded
    }
}

#if os(macOS)
struct ExhibitionWebView: NSViewRepresentable {
    let htmlURL: URL?
    let readAccessURL: URL?
    let revision: Int
    let controller: WebPreviewController

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        controller.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        controller.webView = webView
        guard let htmlURL, let readAccessURL else { return }
        if context.coordinator.lastLoadedRevision != revision {
            context.coordinator.lastLoadedRevision = revision
            webView.loadFileURL(htmlURL, allowingReadAccessTo: readAccessURL)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastLoadedRevision: Int = -1
    }
}
#else
struct ExhibitionWebView: UIViewRepresentable {
    let htmlURL: URL?
    let readAccessURL: URL?
    let revision: Int
    let controller: WebPreviewController

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        controller.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        controller.webView = webView
        guard let htmlURL, let readAccessURL else { return }
        if context.coordinator.lastLoadedRevision != revision {
            context.coordinator.lastLoadedRevision = revision
            webView.loadFileURL(htmlURL, allowingReadAccessTo: readAccessURL)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastLoadedRevision: Int = -1
    }
}
#endif
