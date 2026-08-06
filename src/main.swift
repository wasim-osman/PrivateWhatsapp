import AppKit
import WebKit

private let homeURL = URL(string: "https://web.whatsapp.com")!
private let ephemeralSession = CommandLine.arguments.contains("--ephemeral")
private let noScripts = CommandLine.arguments.contains("--no-scripts")
private let noRetention = CommandLine.arguments.contains("--no-retention")
private let debugMode = CommandLine.arguments.contains("--debug")

private let debugScript = """
(function () {
  function dump(label) {
    try {
      var pane = document.querySelector('#pane-side');
      var main = document.querySelector('#main');
      var out = {
        label: label,
        readyState: document.readyState,
        href: location.href,
        bodyLen: document.body ? document.body.innerHTML.length : -1,
        app: !!document.querySelector('#app'),
        chatList: !!pane,
        chatListVisible: pane ? getComputedStyle(pane).display !== 'none' : false,
        mainVisible: main ? getComputedStyle(main).display !== 'none' : false
      };
      if (window.webkit && window.webkit.messageHandlers) {
        window.webkit.messageHandlers.debugLog.postMessage(JSON.stringify(out));
      }
    } catch (e) {}
  }
  window.addEventListener('error', function (ev) {
    try {
      window.webkit.messageHandlers.debugLog.postMessage('JSERROR: ' + (ev.message || '') + ' @ ' + (ev.filename || '') + ':' + ev.lineno);
    } catch (e) {}
  });
  window.addEventListener('unhandledrejection', function (ev) {
    try {
      var r = ev.reason;
      window.webkit.messageHandlers.debugLog.postMessage('REJECTION: ' + (r && r.message ? r.message : String(r)));
    } catch (e) {}
  });
  dump('start');
  window.addEventListener('load', function () { setTimeout(function () { dump('load+3s'); }, 3000); });
  setInterval(function () { dump('tick'); }, 15000);
})();
"""
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

  var RES = [/get whatsapp for (mac|windows)/i];
  var TAGS = 'div,h1,h2,h3,h4,a,button,span,header,section,p';

  function matches(s) {
    for (var j = 0; j < RES.length; j++) if (RES[j].test(s)) return true;
    return false;
  }

  function hideTextPromo() {
    var els = document.querySelectorAll(TAGS);
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (el.style && el.style.display === 'none') continue;
      if (el.children.length > 12) continue;
      var t = el.textContent || '';
      if (!matches(t)) continue;
      var parent = el.parentElement;
      while (parent && parent !== document.body && matches(parent.textContent || '') && (parent.textContent || '').length < 200) {
        el = parent;
        parent = el.parentElement;
      }
      el.style.display = 'none';
    }
  }
  hideTextPromo();
  setInterval(hideTextPromo, 10000);
})();
"""

private let retentionScript = """
(function () {
  var DAY = 24 * 60 * 60 * 1000;
  var CUTOFF = 15 * DAY;
  var DBS = ['wa-db', 'user-data'];

  function valueTime(v) {
    if (!v) return null;
    var t = v.t;
    if (typeof t === 'number') return t;
    if (t && typeof t === 'object' && typeof t.low === 'number') return t.low;
    var mt = v.messageTimestamp;
    if (typeof mt === 'number') return mt;
    if (mt && typeof mt === 'object' && typeof mt.low === 'number') return mt.low;
    return null;
  }

  function prune() {
    try {
      for (var i = 0; i < DBS.length; i++) {
        (function (name) {
          var open = indexedDB.open(name);
          open.onupgradeneeded = function () {
            open.transaction.abort();
          };
          open.onsuccess = function () {
            var db = open.result;
            db.onversionchange = function () { db.close(); };
            if (!db.objectStoreNames.contains('message')) { db.close(); return; }
            var tx;
            try { tx = db.transaction('message', 'readwrite'); } catch (e) { db.close(); return; }
            var store = tx.objectStore('message');
            var cursor = store.openCursor();
            var cut = Date.now() - CUTOFF;
            var pruned = 0;
            cursor.onsuccess = function () {
              var c = cursor.result;
              if (!c) { db.close(); return; }
              var ts = valueTime(c.value);
              if (ts !== null) {
                var ms = ts > 1e12 ? ts : ts * 1000;
                if (ms < cut) {
                  c.delete();
                  pruned++;
                }
              }
              c.continue();
            };
            cursor.onerror = function () { db.close(); };
            tx.oncomplete = function () {
              if (pruned > 0 && window.console) {
                console.log('WhatsAppSandbox retention: pruned ' + pruned + ' old messages');
              }
            };
          };
          open.onerror = function () {};
        })(DBS[i]);
      }
    } catch (e) {}
  }

  setTimeout(prune, 20000);
  setInterval(prune, 15 * 60 * 1000);
})();
"""

private let heartbeatScript = """
(function () {
  function beat() {
    try { window.webkit.messageHandlers.heartbeat.postMessage('alive'); } catch (e) {}
  }
  beat();
  setInterval(beat, 15000);
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
    private var lastHeartbeat = Date.distantPast
    private var hangRetries = 0
    private var pageDidLoad = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = ephemeralSession ? .nonPersistent() : .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(source: heartbeatScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        contentController.add(self, name: "heartbeat")
        if !noScripts {
            contentController.addUserScript(WKUserScript(source: cleanupScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            contentController.addUserScript(WKUserScript(source: callStateScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            if !noRetention {
                contentController.addUserScript(WKUserScript(source: retentionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            }
        }
        if debugMode {
            contentController.addUserScript(WKUserScript(source: debugScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            contentController.add(self, name: "debugLog")
        }
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

        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.checkHeartbeat()
        }
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageDidLoad = true
        lastHeartbeat = Date()
        hangRetries = 0
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logDebug("web content process terminated")
        handleDeadPage()
    }

    private func checkHeartbeat() {
        guard pageDidLoad, Date().timeIntervalSince(lastHeartbeat) > 75 else { return }
        logDebug("page unresponsive, reloading")
        handleDeadPage()
    }

    private func handleDeadPage() {
        hangRetries += 1
        let delay: Double = hangRetries <= 3 ? 0.5 : 300
        logDebug("reloading (attempt \(hangRetries))")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.webView.reload()
        }
    }

    private func logDebug(_ text: String) {
        guard debugMode else { return }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent("debug.log")
        let line = "[\(Date())] \(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @objc func reloadPage() {
        webView.reload()
    }

    @objc func reloadWithoutCache() {
        let store = WKWebsiteDataStore.default()
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeServiceWorkerRegistrations,
            WKWebsiteDataTypeOfflineWebApplicationCache,
        ]
        store.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            self?.webView.reload()
        }
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
        if message.name == "heartbeat" {
            lastHeartbeat = Date()
            return
        }
        if message.name == "debugLog", let text = message.body as? String {
            logDebug(text)
            return
        }
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
let reloadNoCacheItem = viewMenu.addItem(withTitle: "Reload Without Cache", action: #selector(AppDelegate.reloadWithoutCache), keyEquivalent: "R")
reloadNoCacheItem.target = delegate
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
