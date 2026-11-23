import SwiftUI
#if os(macOS)
import AppKit
import WebKit
#endif

@main
struct DigitalGalleryApp: App {
    init() {
        #if os(macOS)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        scheduleScreenshotIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup("Digital Gallery") {
            ContentView()
                .frame(minWidth: 1140, minHeight: 820)
        }
    }

    #if os(macOS)
    private func scheduleScreenshotIfRequested() {
        let args = CommandLine.arguments
        guard let flagIdx = args.firstIndex(of: "--screenshot"),
              flagIdx + 1 < args.count
        else { return }
        let outPath = args[flagIdx + 1]

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            captureMainWindow(to: outPath)
        }
    }

    private func captureMainWindow(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first,
              let rootView = window.contentView
        else {
            NSApp.terminate(nil)
            return
        }

        rootView.layoutSubtreeIfNeeded()
        let bounds = rootView.bounds

        guard let baseRep = rootView.bitmapImageRepForCachingDisplay(in: bounds) else {
            NSApp.terminate(nil)
            return
        }
        rootView.cacheDisplay(in: bounds, to: baseRep)

        let finish: (NSImage?) -> Void = { webImage in
            let finalImage = NSImage(size: bounds.size)
            finalImage.lockFocus()
            baseRep.draw(in: bounds)
            if let webImage, let webView = findWebView(in: rootView) {
                let targetRect = webView.convert(webView.bounds, to: rootView)
                let clipPath = NSBezierPath(roundedRect: targetRect, xRadius: 34, yRadius: 34)
                NSGraphicsContext.saveGraphicsState()
                clipPath.addClip()
                webImage.draw(
                    in: targetRect,
                    from: NSRect(origin: .zero, size: webImage.size),
                    operation: .copy,
                    fraction: 1.0
                )
                NSGraphicsContext.restoreGraphicsState()
            }
            finalImage.unlockFocus()

            if let tiff = finalImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:])
            {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }

        if let webView = findWebView(in: rootView) {
            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds
            webView.takeSnapshot(with: config) { image, _ in
                finish(image)
            }
        } else {
            finish(nil)
        }
    }

    private func findWebView(in view: NSView) -> WKWebView? {
        if let web = view as? WKWebView {
            return web
        }
        for sub in view.subviews {
            if let found = findWebView(in: sub) {
                return found
            }
        }
        return nil
    }
    #endif
}
