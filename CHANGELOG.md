# Changelog

Newest release on top. Each `## <version>` section is shown in-app: in the
"What's New" popup after an update, and (via release.sh) in Sparkle's update
prompt.

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
