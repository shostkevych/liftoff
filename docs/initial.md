# Afterburn — Initial Plan

Native macOS terminal emulator app, built for running multiple agentic CLI sessions (Claude Code, etc.) across projects.

## Stack

- **SwiftUI** app shell (latest macOS APIs)
- **SwiftTerm** for terminal emulation — `LocalProcessTerminalView` wrapped via `NSViewRepresentable`
- Native PTY, fast rendering, no cross-platform/FFI overhead

## UI Structure

### Top bar — two-level nested tabs

1. **Level 1 — Project tabs**: each tab represents a project folder (working directory)
2. **Level 2 — Terminal tabs (children)**: per-project row of terminal sessions, each running Claude Code or another agentic CLI, spawned in that project's folder

### Panes

- Multiple panes (splits) within a terminal tab

## Decisions

- Swift over Rust: UI is SwiftUI/AppKit anyway; SwiftTerm covers the VT core natively. Rust (Alacritty/WezTerm path) only pays off for cross-platform or custom cores — unnecessary FFI complexity here.
