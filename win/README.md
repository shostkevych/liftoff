# Liftoff for Windows

Native Windows port of Liftoff — the terminal for the AI-agent era. Built in
**C# / WinUI 3** (.NET 8), unpackaged (`.exe` + installer, no MSIX/Store), to stay
as close to the macOS build's native feel as possible.

This is an early scaffold: the portable core (protocol, crypto, PTY, models) is
in place and wire-compatible with the existing iOS/web clients; the UI is a
working shell with a **stopgap** terminal renderer.

## Layout

| Path | What it is | Status |
|---|---|---|
| `src/Liftoff.Core/Crypto/` | ChaCha20Poly1305 + SHA256 token→key | ✅ wire-compatible with macOS/iOS |
| `src/Liftoff.Core/Pty/` | ConPTY interop + `PtySession` (spawn/read/write/resize) | ✅ functional |
| `src/Liftoff.Core/Models/` | `Agent` detection, `TerminalSession`, `Project`, `AppStore` | ✅ ported |
| `src/Liftoff.Core/Protocol/` | `CompanionServer` (TCP 48624 + WS 48625) | ✅ core message types |
| `src/Liftoff.App/` | WinUI 3 app: project rail + terminal `TabView` | 🟡 shell + stopgap renderer |

## Build

Requires Windows 10 1809+, Visual Studio 2022 (17.10+) with the **.NET Desktop**
and **Windows App SDK** workloads, or the CLI:

```powershell
cd win
dotnet build Liftoff.sln -c Debug -p:Platform=x64
dotnet run --project src/Liftoff.App -p:Platform=x64
```

## Wire compatibility

The crypto and companion protocol are deliberate byte-for-byte ports so a phone
already paired to a Mac, and the bundled `web/index.html`, work against the
Windows app unchanged:

- Encrypted payloads use CryptoKit's `combined` layout: `nonce(12) ‖ ciphertext ‖ tag(16)`.
- Key = `SHA256(utf8(token))`; token = base64 of 32 random bytes.
- TCP (companion) payloads are encrypted; WebSocket (browser) payloads are plaintext.
- Message types: `auth`/`authok`/`authfail`/`needauth`/`blocked`, `list`/`sessions`,
  `attach`/`size`/`snapshot`/`output`, `input`, `resize`, `detach`, `close`.

## Roadmap (what's left)

Ordered by how much it blocks a usable app:

1. **Real VT renderer** — the single biggest piece. `AnsiTextFilter` only strips
   escapes so output is legible. Options: embed Windows Terminal's
   `Microsoft.Terminal.Control`, or port SwiftTerm's parser/buffer to a
   Win2D/custom-drawn surface. Everything else assumes this exists.
2. **Agent detection wiring** — `AgentDetection.Detect` is ported, but nothing
   inspects the ConPTY child's foreground process yet. Needs a Toolhelp32/WMI
   (or NtQuery) process walk to feed `TerminalSession.RunningAgent`/`IsBusy`,
   then `CompanionServer.TerminalActivityChanged()`.
3. **Settings + persistence** — token/web-password in Windows Credential Manager
   (DPAPI), project list + colors persisted, pairing **QR** pane.
4. **Protocol gaps** — `open`/`openempty`/`newtab`/`recents`/`upload`/`greeting`
   are TODO in `CompanionServer.Handle`.
5. **Notifications** — Windows toast (`AppNotificationManager`) for agent
   done/waiting, replacing `UserNotifications`.
6. **Web + hook servers** — port `WebServer` (serves `../web`) and the local
   `NotificationServer` that receives agent hook callbacks.
7. **Auto-update** — WinSparkle or a custom updater against the existing appcast.
8. **Sleep guard** — `SetThreadExecutionState` in place of IOKit power assertions.
9. **Packaging/signing** — Authenticode signing + installer (MSI/Inno/WiX).

## Not ported (macOS-only, no Windows equivalent needed)

Xcode/xcodegen project, Sparkle, Keychain (→ Credential Manager), AppKit chrome.
The shared `web/` client and the marketing `site/` live at the repo root and serve
both platforms.
