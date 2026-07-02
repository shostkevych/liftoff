<p align="center">
  <img src="icon.png" width="96" alt="Liftoff icon">
</p>

<h1 align="center">Liftoff</h1>

<p align="center"><b>The terminal for the AI-agent era.</b><br>
A native macOS terminal for engineers who run coding agents across many projects at once.<br>
Watch and steer Claude Code, Codex, Gemini and more — from your Mac, your phone, or any browser.</p>

<p align="center"><a href="https://liftoff.shostkevych.com">liftoff.shostkevych.com</a> · <a href="https://liftoff.shostkevych.com/download">Download for macOS</a></p>

---

## Features

- **Projects × terminals** — top-level tabs per project folder, nested terminal tabs and split panes per project, each running its own agent session.
- **Agent-aware** — detects when Claude Code (or opencode) is working, waiting for input, or done; shows per-session status at a glance and native macOS notifications with project-aware titles.
- **Liftoff Air (iOS companion)** — pair your iPhone by scanning a QR code and monitor or drive every session from your phone over the local network, with end-to-end encrypted traffic.
- **Web access** — a bundled browser client lets you check on sessions from any device.
- **Native & fast** — SwiftUI + [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) with a Metal-accelerated renderer. No Electron, no telemetry, no account.
- **Auto-updates** — signed and notarized releases delivered via [Sparkle](https://sparkle-project.org).

## Repository layout

| Path | What it is |
|---|---|
| `Liftoff/` | macOS app (SwiftUI) |
| `LiftoffAir/` | iOS companion app |
| `SwiftTerm/` | vendored fork of [migueldeicaza/SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT) |
| `web/` | bundled web client served by the app |
| `site/` | Next.js marketing site |
| `scripts/` | release pipeline: build, sign, notarize, DMG, appcast |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) project definition |

## Building from source

Requirements: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/<you>/liftoff.git
cd liftoff
xcodegen                      # regenerates Liftoff.xcodeproj from project.yml
open Liftoff.xcodeproj        # build the Liftoff (macOS) or LiftoffAir (iOS) scheme
```

The checked-in project uses the author's signing team; switch the targets to your own team (or automatic signing) in Xcode, or edit `DEVELOPMENT_TEAM` in `project.yml` and rerun `xcodegen`.

Release builds (`scripts/release.sh`, `scripts/build-dmg.sh`) additionally need a Developer ID certificate and a `notarytool` keychain profile — see the comments at the top of each script.

## License

[MIT](LICENSE). The vendored SwiftTerm fork keeps its original MIT license and copyright.
