# Liftoff Performance Improvements

## P0 — Critical

### 1. Timer Leak — `busyTimer` never invalidated

**File:** `Liftoff/TerminalHostView.swift:68-78`

`startBusyTracking()` creates a 0.25s repeating timer on the main run loop, but `dispose()` only calls `stopAgentPolling()` — it never invalidates `busyTimer`. This timer fires forever (wasteful but not crashing since `[weak self]`).

**Fix:** Add in `dispose()`:
```swift
view.busyTimer?.invalidate()
view.busyTimer = nil
```

---

### 2. Coarse `@Observable` broadcasts — massive over-rendering

**File:** `Liftoff/Models.swift` — `AppStore`

`AppStore` is a single `@Observable` class with ~40 properties. In SwiftUI's observation system, **any** mutation triggers re-renders on **all** views that read `store`. Divider drags call `paneFractions[id] = ...` on every mouse event (60fps), which mutates the store and re-renders the entire `ContentView` tree.

**Impact:** The split layout recalculates all widths, rebuilds all terminal cell views, and re-evaluates all overlay conditions on every pixel of drag. This is the #1 performance bottleneck.

**Fix options:**
- Extract `paneFractions` and `terminalFractions` into separate `@Observable` objects keyed by project, injected per-pane so only the affected pane re-renders.
- Or use `.equatable()` / `withObservationTracking` to limit scope.
- At minimum, debounce `persist()` during drag (see #4).

---

## P1 — High

### 3. Main-thread file I/O — `SettingsStore.save()`

**File:** `Liftoff/SettingsStore.swift:79-86`

`persist()` is called synchronously on the main thread during drag, tag changes, welcome completion, etc. It does `FileManager.createDirectory` + `JSONEncoder.encode` + `Data.write` — all synchronous disk I/O blocking the UI.

**Fix:** Write to a temp file then rename (atomic), or dispatch to a background queue:
```swift
static func save(_ settings: Settings) {
    let data = try? JSONEncoder().encode(settings)
    DispatchQueue.global(qos: .utility).async {
        guard let data else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tmp = directory.appendingPathComponent("settings.tmp")
        try? data.write(to: tmp)
        try? FileManager.default.replaceItem(at: file, withItemAt: tmp)
    }
}
```

---

### 4. `persist()` called on every drag event

**File:** `Liftoff/Models.swift:688-699`

`dragDivider` and `dragTerminalDivider` both modify `paneFractions` and `terminalFractions`, triggering store changes. If any downstream code calls `persist()` on each change (or via other mutations during drag), this is 60+ persists per second of dragging.

**Fix:** Debounce writes:
```swift
private var persistTask: Task<Void, Never>?
func persist() {
    persistTask?.cancel()
    persistTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 500_000_000)
        Self.save(.init(...))
    }
}
```

---

### 5. Agent polling — `sysctl(KERN_PROCARGS2)` every 1.5s per terminal

**File:** `Liftoff/TerminalHostView.swift:106-184`

Each terminal runs a 1.5s timer that calls `sysctl` twice (once for `KERN_PROC_PGRP`, once for `KERN_PROCARGS2` per process in the group). With 5 terminals, that's ~10 `sysctl` calls every 1.5 seconds, each allocating a variable-size buffer. This runs on the main thread.

**Fixes:**
- Move the `sysctl` work off the main thread:
```swift
agentPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
    guard let self, self.process.childfd >= 0 else { return }
    let fd = self.process.childfd
    DispatchQueue.global(qos: .utility).async {
        let cmd = Self.foregroundCommand(pgid: tcgetpgrp(fd))
        DispatchQueue.main.async {
            self.onForegroundCommand?(cmd, fd)
        }
    }
}
```
- Cache the result and skip `sysctl` if `tcgetpgrp()` returns the same pgid as last time.

---

### 6. `updateNSView` focuses terminal on every SwiftUI update

**File:** `Liftoff/TerminalHostView.swift:462-473`

`updateNSView` is called on **every** store change (since the view reads `isActive` from the `@Environment(AppStore)`). Any store mutation (tag prompt, divider drag, overlay toggle) re-evaluates all terminal views and dispatches a `makeFirstResponder` call.

**Fix:** Track the previous `isActive` value and only dispatch when it transitions to `true`:
```swift
private var wasActive = false
func updateNSView(_ nsView: FocusTrackingTerminalView, context: Context) {
    nsView.onFocus = onFocus
    nsView.nativeBackgroundColor = .black
    if isActive && !wasActive {
        DispatchQueue.main.async { ... }
    }
    wasActive = isActive
}
```

---

## P2 — Medium

### 7. Unbounded `inbox` growth in CompanionServer

**File:** `Liftoff/CompanionServer.swift:33`

A malicious or buggy client sending partial data (no newline) causes `inbox` to grow without bound.

**Fix:** Cap the buffer:
```swift
private func drain(_ client: Client) {
    while let nl = client.inbox.firstIndex(of: 0x0A) {
        ...
    }
    if client.inbox.count > 1_000_000 {
        disconnect(client)
    }
}
```

---

### 8. O(n) linear scans for store/project/terminal lookups

**File:** `Liftoff/CompanionServer.swift:302-324`

`store(forProject:)`, `storeAndProject(forPath:)`, `storeAndProject(forTerminal:)` all do nested `first(where:)` loops across all windows, projects, and terminals.

**Fix:** Build indexes:
```swift
// In AppStore:
private static var projectIndex: [UUID: (AppStore, Project)] = [:]
private static var terminalIndex: [UUID: (AppStore, Project)] = [:]
```
Update on project add/remove. This turns remote-command lookups from O(windows × projects × terminals) to O(1).

---

### 9. WebServer reads bundle files on every request

**File:** `Liftoff/WebServer.swift:44-60`

Each HTTP request to `/` or `/icon.png` does `Bundle.main.url(forResource:)` + `Data(contentsOf:)` from disk.

**Fix:** Cache the data at server start:
```swift
private static let indexHTML: Data? = {
    guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web"),
          let data = try? Data(contentsOf: url) else { return nil }
    return Data(http(status: "200 OK", contentType: "text/html; charset=utf-8", body: data))
}()
```

---

### 10. `localIPv4Addresses()` recomputed on every QR popup render

**File:** `Liftoff/Popups.swift:118`

`AirConnectPopup` computes `ips` in its body:
```swift
private var ips: [String] { AirPairing.localIPv4Addresses() }
```

This calls `getifaddrs` + `getnameinfo` for every interface on every SwiftUI body evaluation.

**Fix:** Cache at app start and refresh on `SCNetworkReachability` changes, or at minimum compute once in `init`/`onAppear`.

---

## P3 — Low

### 11. Cerebras API calls — no timeout handling or retry backoff

**File:** `Liftoff/Models.swift:554-566`

`summarizeSelection` has a hardcoded 2-attempt loop with 0.8s sleep. There's no exponential backoff, no cancellation on view dismiss, and the `URLSession` timeout is 30s.

**Fix:** Use `Task` with cancellation support and shorter timeout:
```swift
request.timeoutInterval = 15
// Cancel on view dismiss
```

---

### 12. `CompanionClient` uses `@Published` instead of `@Observable`

**File:** `LiftoffAir/CompanionClient.swift:7`

`CompanionClient` is `ObservableObject` with `@Published` properties. Every published change triggers object-will-change notifications to all subscribers. The 5-second refresh timer + output streaming means this fires constantly, re-rendering the entire session list even when nothing changed.

**Fix:** If targeting iOS 17+, migrate to `@Observable` for fine-grained observation. Or use `Equatable`-based diffing.

---

### 13. `MarkdownText.blocks` computed on every render

**File:** `Liftoff/MarkdownText.swift:62-103`

The `blocks` property recomputes on every body evaluation. For long summaries, this parses the entire markdown string each time.

**Fix:** Cache with `@State` or compute once in `init`.