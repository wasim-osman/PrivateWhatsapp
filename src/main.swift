import AppKit
import WebKit

private let homeURL = URL(string: "https://web.whatsapp.com")!
private let ephemeralSession = CommandLine.arguments.contains("--ephemeral")
private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Safari/605.1.15"
private let callStateScript = """
(function () {
  function check() {
    var accept = document.querySelector('[aria-label^="Accept"]');
    var decline = document.querySelector('[aria-label^="Decline"]');
    var incoming = !!(accept && decline);
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.callState) {
      window.webkit.messageHandlers.callState.postMessage({ incoming: incoming });
    }
  }
  check();
  setInterval(check, 1000);
})();
"""

private let cleanupScript = """
(function () {
  var css = [
    '[data-testid="meta-ai-button"]',
    '[data-testid="desktopDownloadBanner"]',
    '[aria-label="Meta AI"]'
  ].join(',') + '{display:none !important;visibility:hidden !important;pointer-events:none !important;}';
  var style = document.createElement('style');
  style.textContent = css;
  (document.head || document.documentElement).appendChild(style);

  var RE = /get whatsapp for (mac|windows)/i;
  var TAGS = 'div,h1,h2,h3,h4,a,button,span,header,section,p';

  function hideTextPromo() {
    var els = document.querySelectorAll(TAGS);
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (el.style && el.style.display === 'none') continue;
      if (el.children.length > 12) continue;
      var t = el.textContent || '';
      if (!RE.test(t)) continue;
      var parent = el.parentElement;
      while (parent && parent !== document.body && RE.test(parent.textContent || '') && (parent.textContent || '').length < 400) {
        el = parent;
        parent = el.parentElement;
      }
      el.style.display = 'none';
    }
  }
  hideTextPromo();
  setInterval(hideTextPromo, 2000);
})();
"""

final class CallBannerContainer: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var callBanner: NSView?
    private var callBannerLabel: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = ephemeralSession ? .nonPersistent() : .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(source: cleanupScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        contentController.addUserScript(WKUserScript(source: callStateScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        contentController.add(self, name: "callState")
        configuration.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WhatsApp Sandbox"
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.load(URLRequest(url: homeURL))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    func webView(_ webView: WKWebView, requestGeolocationPermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    func webView(_ webView: WKWebView, requestNotificationPermissionFor origin: WKSecurityOrigin, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        switch scheme {
        case "https", "http":
            if navigationAction.navigationType == .linkActivated,
               let host = url.host?.lowercased(),
               !isWhatsAppHost(host) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        case "about", "blob", "data":
            decisionHandler(.allow)
        default:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }

    private func isWhatsAppHost(_ host: String) -> Bool {
        host == "whatsapp.com" || host.hasSuffix(".whatsapp.com")
    }

    @objc func reloadPage() {
        webView.reload()
    }

    @objc func zoomIn() {
        webView.magnification = min(webView.magnification + 0.1, 3.0)
    }

    @objc func zoomOut() {
        webView.magnification = max(webView.magnification - 0.1, 0.3)
    }

    @objc func zoomActualSize() {
        webView.magnification = 1.0
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "callState",
              let body = message.body as? [String: Any],
              let incoming = body["incoming"] as? Bool else { return }
        if incoming {
            showCallBanner()
        } else {
            hideCallBanner()
        }
    }

    private func showCallBanner() {
        if callBanner == nil, let content = window.contentView {
            let container = CallBannerContainer(frame: NSRect(x: 0, y: content.bounds.height - 52, width: content.bounds.width, height: 52))
            container.autoresizingMask = [.width, .minYMargin]
            let label = NSTextField(labelWithString: "Incoming call — answer on another device")
            label.textColor = .white
            label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            label.sizeToFit()
            let pill = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.width + 36, height: 34))
            pill.wantsLayer = true
            pill.layer?.backgroundColor = NSColor(calibratedRed: 0.07, green: 0.549, blue: 0.494, alpha: 0.95).cgColor
            pill.layer?.cornerRadius = 17
            label.setFrameOrigin(NSPoint(x: 18, y: (34 - label.frame.height) / 2))
            pill.addSubview(label)
            container.addSubview(pill)
            pill.setFrameOrigin(NSPoint(x: (container.bounds.width - pill.frame.width) / 2, y: 9))
            content.addSubview(container)
            callBanner = container
            callBannerLabel = label
        }
        guard let banner = callBanner else { return }
        banner.alphaValue = 0
        banner.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            banner.animator().alphaValue = 1
        }
    }

    private func hideCallBanner() {
        guard let banner = callBanner, !banner.isHidden else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            banner.animator().alphaValue = 0
        } completionHandler: {
            banner.isHidden = true
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

let mainMenu = NSMenu()

let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "About WhatsApp Sandbox", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
appMenu.addItem(.separator())
appMenu.addItem(withTitle: "Hide WhatsApp Sandbox", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
appMenu.addItem(withTitle: "Quit WhatsApp Sandbox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenuItem.submenu = appMenu

let editMenuItem = NSMenuItem()
mainMenu.addItem(editMenuItem)
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editMenuItem.submenu = editMenu

let viewMenuItem = NSMenuItem()
mainMenu.addItem(viewMenuItem)
let viewMenu = NSMenu(title: "View")
let reloadItem = viewMenu.addItem(withTitle: "Reload", action: #selector(AppDelegate.reloadPage), keyEquivalent: "r")
reloadItem.target = delegate
viewMenu.addItem(.separator())
let zoomInItem = viewMenu.addItem(withTitle: "Zoom In", action: #selector(AppDelegate.zoomIn), keyEquivalent: "+")
zoomInItem.target = delegate
let zoomOutItem = viewMenu.addItem(withTitle: "Zoom Out", action: #selector(AppDelegate.zoomOut), keyEquivalent: "-")
zoomOutItem.target = delegate
let actualSizeItem = viewMenu.addItem(withTitle: "Actual Size", action: #selector(AppDelegate.zoomActualSize), keyEquivalent: "0")
actualSizeItem.target = delegate
viewMenuItem.submenu = viewMenu

let windowMenuItem = NSMenuItem()
mainMenu.addItem(windowMenuItem)
let windowMenu = NSMenu(title: "Window")
windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
windowMenuItem.submenu = windowMenu

app.mainMenu = mainMenu
app.run()
