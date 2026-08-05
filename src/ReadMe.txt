WhatsApp Sandbox for macOS
==========================

A hardened, sandboxed wrapper for WhatsApp Web.
Native Swift + WKWebView inside the macOS App Sandbox.

INSTALL
-------
1. Drag WhatsAppSandbox.app into your Applications folder.
2. First launch: right-click the app -> Open.
   (The app is ad-hoc signed, so Gatekeeper asks once.)

SECURITY
--------
The app has exactly one sandbox privilege: network access.
No filesystem, camera, microphone, location, notifications,
printing, popups, or drag-and-drop file access.

USAGE
-----
- Scan the QR code once; your login is remembered.
- External links open in your default browser.
- Quit with Cmd+Q.
- Run with --ephemeral for a fully forget-everything session.

SOURCE
------
Source code, release notes and build instructions:
https://github.com/wasim-osman/PrivateWhatsapp
