import Nav from "./components/Nav";
import HeroDemo from "./components/HeroDemo";

const GITHUB = "https://github.com/shostkevych/liftoff";
const APP_STORE = "https://apps.apple.com/us/app/liftoff-air/id6780915535";
// Latest published, signed macOS release.
const DOWNLOAD = "/download";

function Icon({ d }) {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
      <path d={d} stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/* Brand marks for the agentic CLIs Liftoff detects.
   Logos come from the selfhst/icons CDN — the same source the launcher uses. */
const SELFHST = "https://cdn.jsdelivr.net/gh/selfhst/icons@main/svg";
const AGENT_SLUGS = {
  claude: "claude",
  openai: "openai",
  gemini: "google-gemini",
  grok: "grok",
  copilot: "github-copilot",
};

function AgentLogo({ name, size = 28 }) {
  const slug = AGENT_SLUGS[name];
  if (slug) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img src={`${SELFHST}/${slug}.svg`} alt="" width={size} height={size} loading="lazy" />
    );
  }
  const common = { width: size, height: size, viewBox: "0 0 24 24", "aria-hidden": true };
  switch (name) {
    case "cursor":
      return (
        <svg {...common} fill="#fff">
          <path d="M12 2 21 7v10l-9 5-9-5V7l9-5Zm0 2.1L5 8v8l7 3.9 7-3.9V8l-7-3.9ZM12 6.6 17 9.5v5L12 17.4 7 14.5v-5L12 6.6Z" />
        </svg>
      );
    case "opencode":
      return (
        <svg {...common} fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M9 8 5 12l4 4M15 8l4 4-4 4" />
        </svg>
      );
    default:
      return null;
  }
}

const AGENTS = [
  ["claude", "Claude"],
  ["openai", "Codex"],
  ["gemini", "Gemini"],
  ["grok", "Grok"],
  ["opencode", "opencode"],
  ["copilot", "Copilot"],
  ["cursor", "Cursor"],
];

const MINI = [
  {
    t: "Instant Terminal",
    d: "Press ⌘I from any app to bring up a fresh floating terminal.",
  },
  {
    t: "Splits, zoom & focus",
    d: "Split, expand to full focus, and zoom type on the fly.",
  },
  {
    t: "Color-coded workspaces",
    d: "Manage reusable project tags and colors in native Settings.",
  },
  {
    t: "Undo a closed tab",
    d: "Restore a terminal within 10 seconds, with its process and scrollback intact.",
  },
  {
    t: "Memory at a glance",
    d: "See memory usage by terminal and close a shell that gets too heavy.",
  },
  {
    t: "Pin your projects",
    d: "Keep your regular workspaces ready to reopen when Liftoff starts.",
  },
  {
    t: "Files into the shell",
    d: "Drop files or folders onto a terminal to paste their shell-escaped paths.",
  },
  {
    t: "Tips as you work",
    d: "Discover useful shortcuts and workflow hints, or turn them off in Help.",
  },
  {
    t: "Native macOS, fast",
    d: "A real SwiftUI app on a battle-tested core. Quiet, keyboard-first.",
  },
];

/* Keyboard-first workflow shortcuts (verbatim from the in-app ⌘H reference). */
const KEYS = [
  { k: ["⌘", "⇧"], t: "Quick switcher", d: "Hold to open; ←/→ switches Projects and Shortcuts, ↑/↓ chooses, and release confirms." },
  { k: ["⌘", "O"], t: "Open project", d: "Recents picker with ⌘-click multi-select." },
  { k: ["⌘", "T"], t: "New terminal", d: "Spin up a fresh tab in the focused project." },
  { k: ["⌘", "D"], t: "Split pane", d: "Split the focused terminal side by side." },
  { k: ["⌘", "1–5"], t: "Resize split", d: "Snap a split to n/(n+1) of the project width." },
  { k: ["⌘", "E"], t: "Expand & focus", d: "Blow the focused split up to fill the project." },
  { k: ["⌘", "I"], t: "Instant Terminal", d: "Summon a fresh floating shell from any app. Press again to dismiss." },
  { k: ["⌘", "⇧", "T"], t: "Restore closed tab", d: "Bring a terminal back within 10 seconds, including its running shell." },
  { k: ["⌘", "R"], t: "Rename tab", d: "Give the active terminal a name that running programs cannot overwrite." },
  { k: ["⌘", "L"], t: "Toggle tab bars", d: "Show or hide terminal tab bars across your projects." },
  { k: ["⇧", "↩"], t: "Multiline prompts", d: "Add a newline without submitting in supported coding agents." },
  { k: ["⌘", "B"], t: "Toggle sidebar", d: "Collapse the projects rail for full width." },
];

function Kbd({ keys }) {
  return (
    <span className="kbd-set">
      {keys.map((k, i) => (
        <kbd className="kbd" key={i}>{k}</kbd>
      ))}
    </span>
  );
}

/* Framed product mock — a macOS window shell with custom body content. */
function Frame({ title, children }) {
  return (
    <div className="frame">
      <div className="frame-bar">
        <div className="lights"><i /><i /><i /></div>
        {title ? <span className="frame-ttl">{title}</span> : null}
      </div>
      <div className="frame-body">{children}</div>
    </div>
  );
}

export default function Home() {
  return (
    <>
      <div className="aurora"><i /></div>
      <div className="grain" />
      <Nav />

      <main id="top">
        {/* ---------------- HERO ---------------- */}
        <header className="hero">
          <div className="wrap">
            <span className="eyebrow rise" style={{ animationDelay: "0ms" }}>
              Free &amp; open source
            </span>
            <img
              className="hero-logo rise"
              src="/logo.png"
              alt="Liftoff"
              width={96}
              height={96}
              style={{ animationDelay: "40ms" }}
            />
            <h1 className="display rise" style={{ animationDelay: "70ms" }}>
              Keep every agent in view.
            </h1>
            <p className="lede rise" style={{ animationDelay: "170ms" }}>
              Liftoff is a macOS terminal for engineers who run coding agents
              across many projects at once. Organize your workspaces, reuse your
              prompts, and take your terminals with you on iPhone or in a browser.
            </p>
            <div className="hero-cta rise" style={{ animationDelay: "280ms" }}>
              <a href={DOWNLOAD} className="btn btn-primary">
                Download for macOS
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none">
                  <path d="M12 3v12m0 0 4-4m-4 4-4-4M5 21h14" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </a>
              <span className="cta-soon">
                <b>Free for macOS</b> · Liftoff Air for iPhone
              </span>
            </div>
            <p className="hero-note rise" style={{ animationDelay: "360ms" }}>
              Liftoff 1.18. No account. No terminal data collected. MIT licensed.
            </p>
          </div>

          <div className="wrap stage rise" style={{ animationDelay: "460ms" }}>
            <HeroDemo />
          </div>

          <a className="hero-credit" href="https://www.spacex.com/" target="_blank" rel="noreferrer">
            Backdrop © SpaceX
          </a>
        </header>

        {/* ---------------- TRUSTED BY (agents) ---------------- */}
        <section className="trust-sec">
          <div className="wrap">
            <div className="mini-head">
              <span className="kicker">Agents</span>
              <h2 className="display">Works with your favourite CLI.</h2>
            </div>
            <div className="trust-grid">
              {AGENTS.map(([n, label]) => (
                <div className="trust-cell" key={n} title={label}>
                  <AgentLogo name={n} size={26} />
                  <span>{label}</span>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ---------------- SHOWCASE: projects ---------------- */}
        <section id="features" className="showcase">
          <div className="wrap show-row">
            <div className="show-copy">
              <span className="kicker">Workspace</span>
              <h2 className="display">Every project in one sidebar.</h2>
              <p>
                Give each project its own terminals, reusable color tags, and
                space to work. Click to switch, or ⌘-click to keep several projects
                visible side by side. Open a standalone terminal when you just
                need a shell.
              </p>
              <a href="#air" className="show-link">See it in motion <span className="arr">→</span></a>
            </div>
            <div className="show-visual">
              <Frame title="liftoff">
                <div className="m-app">
                  <div className="m-side">
                    <div className="m-side-head">
                      <span>Projects</span>
                      <span className="m-side-acts"><i /><i /></span>
                    </div>
                    {[
                      { c: "#6fbf93", n: "atlas-api", t: "1 tab open" },
                      { c: "#a07ce0", n: "nimbus", t: "1 tab open", tag: "Work", tagc: "#a07ce0", busy: true },
                      { c: "#3fb6c2", n: "orbit-ui", t: "2 tabs open", tag: "Personal", tagc: "#3fb6c2", active: true },
                    ].map((p) => (
                      <div className={`m-proj${p.active ? " on" : ""}`} key={p.n}>
                        <span className="m-proj-bar" style={{ background: p.c }} />
                        <span className="m-proj-txt">
                          <b>{p.n}</b>
                          <em>{p.t}</em>
                        </span>
                        {p.tag ? (
                          <span className="m-proj-tag" style={{ color: p.tagc, borderColor: p.tagc }}>{p.tag}</span>
                        ) : null}
                        {p.busy ? <span className="m-proj-spin" /> : null}
                      </div>
                    ))}
                  </div>
                  <div className="m-main">
                    <span className="m-bar" style={{ background: "#3fb6c2", width: "32%" }} />
                    <i style={{ width: "78%" }} /><i style={{ width: "92%" }} /><i style={{ width: "60%" }} /><i style={{ width: "84%" }} /><i style={{ width: "70%" }} /><i style={{ width: "48%" }} />
                  </div>
                </div>
              </Frame>
            </div>
          </div>
        </section>

        {/* ---------------- SHOWCASE: prompt shortcuts ---------------- */}
        <section id="prompt-shortcuts" className="showcase">
          <div className="wrap show-row rev">
            <div className="show-copy">
              <span className="kicker">Prompt Shortcuts</span>
              <h2 className="display">Your best prompts, always at hand.</h2>
              <p>
                Save the prompts you reach for in native Settings. Hold ⌘⇧,
                switch to Shortcuts with ← or →, choose with ↑ or ↓, and release
                to paste into the active terminal. Review or edit before you send.
              </p>
              <p>Stored on your Mac. Reusable with any agent or shell. Pasting never submits the prompt for you.</p>
              <a href="#keyboard" className="show-link">Find your next shortcut <span className="arr">→</span></a>
            </div>
            <div className="show-visual">
              <Frame title="Quick Switch">
                <div className="m-shortcuts" aria-label="Example of the prompt shortcut picker">
                  <div className="m-shortcut-modes"><span>Projects</span><strong>Shortcuts</strong></div>
                  {[
                    ["Review changes", "Review the current diff for bugs and missing edge cases."],
                    ["Explain a failure", "Explain what failed and suggest the smallest useful fix."],
                    ["Update documentation", "Update the relevant documentation to match these changes."],
                  ].map(([name, prompt], i) => (
                    <div className={`m-shortcut${i === 0 ? " selected" : ""}`} key={name}>
                      <span className="m-shortcut-number">{i + 1}</span>
                      <div><b>{name}</b><p>{prompt}</p></div>
                    </div>
                  ))}
                  <div className="m-shortcut-hint">↑ ↓ to choose <span>Release ⌘⇧ to paste</span></div>
                </div>
              </Frame>
            </div>
          </div>
        </section>

        {/* ---------------- MINI FEATURES (auto slider) ---------------- */}
        <section className="mini-sec">
          <div className="wrap">
            <div className="mini-head">
              <span className="kicker">Built around agents</span>
              <h2 className="display">Small details. A smoother working day.</h2>
            </div>
            <div className="slider">
              <div className="slider-track">
                {[...MINI, ...MINI].map((f, i) => (
                  <div className="slide" key={i} aria-hidden={i >= MINI.length}>
                    <h3>{f.t}</h3>
                    <p>{f.d}</p>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </section>

        {/* ---------------- AGENT UPDATES ---------------- */}
        <section id="agent-updates" className="showcase">
          <div className="wrap show-row">
            <div className="show-copy">
              <span className="kicker">Agent updates</span>
              <h2 className="display">Know what needs you next.</h2>
              <p>
                Claude Code and Codex send their own completion and attention
                messages. The latest note stays under its terminal in the
                sidebar, with a native macOS notification when you are elsewhere.
              </p>
              <ul className="feature-list">
                <li>Task-aware tab titles keep work easy to find.</li>
                <li>Agent messages stay attached to the right project and terminal.</li>
                <li>Choose your own notification sound in Settings.</li>
              </ul>
              <p className="release-note">Included in Liftoff 1.18, with Claude Code and Codex integrations configured from the app.</p>
            </div>
            <div className="show-visual">
              <Frame title="Agent updates">
                <div className="m-agent-updates" aria-label="Examples of agent messages in the sidebar">
                  <div className="m-agent-note">
                    <div><AgentLogo name="openai" size={20} /><b>Polish settings</b><span>Codex</span></div>
                    <p>Settings updated. Ready for review.</p>
                  </div>
                  <div className="m-agent-note">
                    <div><AgentLogo name="claude" size={20} /><b>Connect billing</b><span>Claude</span></div>
                    <p>Needs input: choose which account to connect.</p>
                  </div>
                  <div className="m-notification-sound"><span>Notification sound</span><b>Custom upload</b></div>
                </div>
              </Frame>
            </div>
          </div>
        </section>

        {/* ---------------- SHOWCASE: Air (mobile) ---------------- */}
        <section id="air" className="showcase">
          <div className="wrap show-row">
            <div className="show-copy">
              <span className="kicker kicker-lg">Air</span>
              <h2 className="display">Your terminals, in your pocket.</h2>
              <p>
                Agents run for minutes — with Air you don&apos;t have to sit and
                watch. Mirror any terminal to your phone from anywhere, with a
                seamless Direct connection at home and encrypted Relay access away.
              </p>
              <div className="air-steps">
                <div className="air-step"><span className="n">1</span> Pair with a QR scan, secured by Face ID.</div>
                <div className="air-step"><span className="n">2</span> Live-mirror any terminal and send input.</div>
                <div className="air-step"><span className="n">3</span> Or open the built-in web client in any browser.</div>
              </div>
              <div className="air-cta">
                <a href={APP_STORE} className="btn btn-primary" target="_blank" rel="noreferrer">
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                    <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.53 4.08ZM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25Z" />
                  </svg>
                  Download on the App Store
                </a>
              </div>
            </div>
            <div className="show-visual show-visual--phone">
              <div className="phone phone-video">
                <div className="screen">
                  <video
                    className="demo-video-mobile"
                    autoPlay
                    muted
                    loop
                    playsInline
                    preload="metadata"
                    poster="/demo-mobile-poster.jpg"
                  >
                    <source src="/demo-mobile.webm" type="video/webm" />
                    <source src="/demo-mobile.mp4" type="video/mp4" />
                  </video>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* ---------------- KEYBOARD ---------------- */}
        <section id="keyboard" className="keys-sec">
          <div className="wrap">
            <div className="mini-head">
              <span className="kicker">Keyboard-first</span>
              <h2 className="display">Hands on the keys. Always.</h2>
              <p className="keys-lede">
                Switch projects, paste saved prompts, restore a closed tab, or
                summon a shell from another app. Keep the everyday moves within
                reach.
              </p>
            </div>
            <div className="keys-grid">
              {KEYS.map((s) => (
                <div className="key-cell" key={s.t}>
                  <Kbd keys={s.k} />
                  <div className="key-txt">
                    <b>{s.t}</b>
                    <span>{s.d}</span>
                  </div>
                </div>
              ))}
            </div>
            <p className="keys-foot">
              <kbd className="kbd">⌘</kbd><kbd className="kbd">H</kbd>
              opens the full hotkeys reference anytime.
            </p>
          </div>
        </section>

        {/* ---------------- PRIVACY ---------------- */}
        <section id="privacy" className="privacy-sec">
          <div className="wrap">
            <div className="priv-head">
              <span className="kicker">Full privacy</span>
              <h2 className="display">Private, even through the cloud.</h2>
              <p>
                Air encrypts the complete relayed session end to end. The thin relay
                only connects your devices and forwards opaque ciphertext; it never
                receives the pairing key and cannot read your terminal content.
              </p>
            </div>
            <div className="priv-grid">
              <div className="priv-cell">
                <div className="mfeat-ico"><Icon d="M12 2 4 6v6c0 5 3.4 8.5 8 10 4.6-1.5 8-5 8-10V6l-8-4ZM9.5 12l1.8 1.8L15 10" /></div>
                <h4>End-to-end encrypted</h4>
                <p>ChaCha20-Poly1305 protects relayed commands, output, and session data with a key derived from your private pairing secret.</p>
              </div>
              <div className="priv-cell">
                <div className="mfeat-ico"><Icon d="M5 12a7 7 0 0 1 14 0M2 12h2m16 0h2M12 2v2M12 19v3M7 12a5 5 0 0 1 10 0M12 12h.01" /></div>
                <h4>Lift off from anywhere</h4>
                <p>Relay connects immediately from anywhere, then Air upgrades to a faster Direct path automatically whenever your Mac is reachable locally.</p>
              </div>
              <div className="priv-cell">
                <div className="mfeat-ico"><Icon d="M13 2 4 14h7l-1 8 9-12h-7l1-8Z" /></div>
                <h4>Optimized &amp; fast</h4>
                <p>A lean native pipeline keeps latency low and battery friendly — and it works with any coding agent, any shell, and any workflow.</p>
              </div>
            </div>
          </div>
        </section>

        {/* ---------------- BOTTOM CTA ---------------- */}
        <section id="open-source" className="cta">
          <div className="wrap">
            <span className="badge">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                <path d="M9 18c-4 1.5-4-2-6-2.5M15 21v-3.5c0-1 .3-1.7.8-2.2-2.8-.3-5.8-1.4-5.8-6 0-1.3.5-2.4 1.2-3.2-.1-.3-.5-1.6.1-3.2 0 0 1-.3 3.3 1.2a11 11 0 0 1 6 0C18.9 2.4 19.9 2.7 19.9 2.7c.6 1.6.2 2.9.1 3.2.7.8 1.2 1.9 1.2 3.2 0 4.6-3 5.7-5.8 6 .5.4.9 1.3.9 2.5V21" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              MIT · free forever
            </span>
            <h2 className="display">Open source and hardened.</h2>
            <p>
              SwiftUI, a hardened terminal core, and an iOS companion you can
              read, fork and build yourself — with end-to-end encryption for
              every Air session. No paywalls or accounts. Anonymous app counters
              never include your commands, prompts, or terminal output.
            </p>
            <div className="cta-btns">
              <a href={DOWNLOAD} className="btn btn-primary">Download for macOS</a>
              <a href={APP_STORE} className="btn btn-ghost" target="_blank" rel="noreferrer">Get Liftoff Air for iOS</a>
              <a href={GITHUB} className="btn btn-ghost" target="_blank" rel="noreferrer">Star on GitHub <span className="arr">→</span></a>
            </div>
          </div>
        </section>
      </main>

      {/* ---------------- FOOTER ---------------- */}
      <footer>
        <div className="wrap foot">
          <a href="#top" className="brand">
            <img className="brand-logo" src="/logo.png" alt="Liftoff" width={26} height={26} />
            Liftoff
          </a>
          <div className="foot-links">
            <a href="#features">Features</a>
            <a href="#prompt-shortcuts">Prompt Shortcuts</a>
            <a href="#agent-updates">Agent updates</a>
            <a href="#keyboard">Shortcuts</a>
            <a href="#air">Air</a>
            <a href="/changelog">Changelog</a>
            <a href="/privacy">Privacy</a>
            <a href="/terms">Terms</a>
            <a href={GITHUB} target="_blank" rel="noreferrer">GitHub</a>
          </div>
          <span>© {new Date().getFullYear()} Liftoff · MIT licensed</span>
        </div>
      </footer>
    </>
  );
}
