# Changelog

Newest release on top. Each `## <version>` section is shown in-app: in the
"What's New" popup after an update, and (via release.sh) in Sparkle's update
prompt.

## 1.11

- Liftoff Air now connects remotely through a thin cloud relay, with the entire relayed session protected end-to-end using ChaCha20-Poly1305
- Relay connects first for dependable remote access, then Liftoff Air silently upgrades to a faster Direct connection when the Mac is reachable locally
- Pairing remains a single QR scan; saved network addresses are never shown and are probed privately in the background
- Connection status clearly shows whether Liftoff Air is using Relay or Direct
- Improved Instant Terminal focus when summoned over another active app

## 1.10

- New: Instant Terminal — press Cmd+I anywhere, even when Liftoff isn't the active app, to summon a floating shell at your home folder, centered on the screen under your cursor
- Each summon starts a fresh shell and focuses it immediately, so you can start typing right away; press Cmd+I again to dismiss
- It floats above other apps, so you can click out to copy something and paste it back — drag the grip in the top-right corner to reposition it

## 1.9

- New: Cmd+Shift+T restores a recently closed terminal tab — the shell is kept alive for 10 seconds after closing, so scrollback and running processes come back exactly as they were
- Restoring works from any close path (Cmd+W, tab ✕, right-click, Liftoff Air), and reopens the project pane if closing the tab closed it
- Up to 5 closed tabs can be restored, newest first

## 1.8

- New: rename tabs — press Cmd+R or right-click a tab to set a custom name; programs running inside the terminal can't overwrite it
- Clear the custom name (or save it empty) to return to automatic titles
- Custom tab names carry over to Liftoff Air and the web client

## 1.7.2

- Removed auth rate limiting — a single stale pairing could lock a device out for minutes, rejecting even the correct token
- Liftoff Air: connection diagnostics logging (visible in Console.app) to make pairing issues easy to trace

## 1.7.1

- Fixed: phone pairing broke after any settings change — the pairing token was wiped on save, so Liftoff Air ended up stuck on "Connecting…" until re-paired. Re-scan the Air code once after this update.

## 1.7

- Fixed: closing a terminal no longer drops connected phones — they just return to the session list
- Air hardening: session updates are only sent to authenticated devices
- Air hardening: encryption now fails closed — no plaintext fallback for terminal output or snapshots
- Better auth rate limiting: tracked per device address, so retries can't bypass the backoff

## 1.6

- New: a "What's New" popup shows the changelog right after each update
- Sparkle update prompts now include the release notes before you install

## 1.5

- opencode notifications now match Claude Code: native banners on stop and permission prompts
- Encrypted iOS pairing: Air traffic is end-to-end encrypted, keys held in the Keychain
- New menu-bar status item with per-session agent activity
- Faster everywhere: async settings writes, debounced persistence, capped inbox, cached markdown rendering
- Sparkle auto-updates with signed, notarized releases
