# WhatsApp Sandbox

A hardened, sandboxed wrapper for [WhatsApp Web](https://web.whatsapp.com/) for macOS.

Native **Swift + WKWebView** — no Electron, no Chromium — running inside the macOS **App Sandbox** with exactly one privilege: a network connection.

## Why

Official desktop messengers are large, privileged applications. This wrapper takes the opposite approach: WhatsApp Web lives in an OS-enforced sandbox that blocks access to your machine — no filesystem, no camera, no microphone, no location, no notifications — while still letting you chat, send attachments, and make audio calls.

## Security model

| Privilege | Status |
|---|---|
| Network (HTTPS) | ✅ Allowed — the only sandbox entitlement |
| Filesystem read/write | ❌ Denied (downloads silently fail; nothing persists outside the app's private container) |
| Camera / microphone | ❌ Denied (never prompts, ever) |
| Location | ❌ Denied |
| Notifications | ❌ Denied |
| Popups / new windows | ❌ Blocked |
| Non-web URL schemes (`file://`, `mailto:`, …) | ❌ Blocked |
| Drag-and-drop file access | ❌ Blocked |
| Printing | ❌ Denied |
| Session storage | 🔒 In the app's private container (or fully in-memory with `--ephemeral`) |

Attaching files still works — the OS file picker is explicit user input, not implicit access. External links open in your default browser, never inside the sandbox.

## Features

- **Persistent login** — scan the QR code once; your session survives quitting
- **Modern Safari user agent** — no "your browser is out of date" screen
- **Full menu bar** — ⌘Q, ⌘C/⌘V/⌘X/⌘A, ⌘R reload, ⌘+ / ⌘− zoom, ⌘M minimize
- **`--ephemeral` mode** — launch with the flag for zero persistence: every quit forgets everything
- **Generated icon** — WhatsApp-inspired, reproducible from `scripts/AppIcon.swift`

## Install

1. Download `WhatsAppSandbox-1.0.dmg` from the [Releases](https://github.com/wasim-osman/PrivateWhatsapp/releases) section.
2. Open the DMG and drag **WhatsAppSandbox.app** into your Applications folder.
3. First launch: right-click the app → **Open** (it's ad-hoc signed, so Gatekeeper asks once — after that it runs normally).

## Build from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```sh
make            # build the app bundle in build/
make run        # build + launch
make install    # copy to /Applications
make dmg        # package dist/WhatsAppSandbox-1.0.dmg
make verify     # check code signature + entitlements
make clean
```

Run in strict mode with:

```sh
./build/WhatsAppSandbox.app/Contents/MacOS/WhatsAppSandbox --ephemeral
```

## Disclaimer

Personal project, not affiliated with Meta/WhatsApp. WhatsApp is a trademark of WhatsApp LLC; the app icon is inspired by it, not a copy of the official logo.
