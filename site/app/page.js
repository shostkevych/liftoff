import Nav from "./components/Nav";
import HeroDemo from "./components/HeroDemo";

const GITHUB = "https://github.com/shostkevych/liftoff";
const APP_STORE = "https://apps.apple.com/us/app/liftoff-air/id6780915535";
// Direct download of the latest signed macOS build (also the Sparkle update feed).
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
    t: "Summarize on the spot",
    d: "Instant AI summaries of long runs and stack traces.",
    d2: "M4 6h16M4 12h10M4 18h7M16 15l2 2 4-4",
  },
  {
    t: "Splits, zoom & focus",
    d: "Split, expand to full focus, and zoom type on the fly.",
    d2: "M4 4h16v16H4zM4 10h16M10 10v10",
  },
  {
    t: "Color-coded workspaces",
    d: "Every project keeps its accent across Mac, phone and web.",
    d2: "M12 3a9 9 0 1 0 9 9 4 4 0 0 1-4-4 4 4 0 0 1-4-4 .9.9 0 0 0-1-1ZM7.5 12a.5.5 0 1 1 0 .01M12 7a.5.5 0 1 1 0 .01M16 11a.5.5 0 1 1 0 .01",
  },
  {
    t: "Native macOS, fast",
    d: "A real SwiftUI app on a battle-tested core. Quiet, keyboard-first.",
    d2: "M13 2 4 14h7l-1 8 9-12h-7l1-8Z",
  },
];

/* Keyboard-first workflow shortcuts (verbatim from the in-app ⌘H reference). */
const KEYS = [
  { k: ["⌘", "⇧", "1–5"], t: "Switch project", d: "Hold ⌘⇧, hit a number — jump straight to any open project." },
  { k: ["⌘", "O"], t: "Open project", d: "Recents picker with ⌘-click multi-select." },
  { k: ["⌘", "T"], t: "New terminal", d: "Spin up a fresh tab in the focused project." },
  { k: ["⌘", "D"], t: "Split pane", d: "Split the focused terminal side by side." },
  { k: ["⌘", "1–5"], t: "Resize split", d: "Snap a split to n/(n+1) of the project width." },
  { k: ["⌘", "E"], t: "Expand & focus", d: "Blow the focused split up to fill the project." },
  { k: ["⌘", "F"], t: "Summarize", d: "Turn selected output into a crisp AI summary." },
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
              Mission control for every project.
            </h1>
            <p className="lede rise" style={{ animationDelay: "170ms" }}>
              Liftoff is a macOS terminal for engineers who run coding agents
              across many projects at once. Watch and steer Claude Code, Codex
              and more — from your Mac, your phone, or any browser.
            </p>
            <div className="hero-cta rise" style={{ animationDelay: "280ms" }}>
              <a href={DOWNLOAD} className="btn btn-primary">
                Download for macOS
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none">
                  <path d="M12 3v12m0 0 4-4m-4 4-4-4M5 21h14" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </a>
              <span className="cta-soon">
                <b>Windows &amp; Linux</b> coming as demand grows
              </span>
            </div>
            <p className="hero-note rise" style={{ animationDelay: "360ms" }}>
              No account. No telemetry. MIT licensed.
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
                Each repository you&apos;re working on gets a row in the sidebar —
                colour-coded, with its open tabs and live activity at a glance.
                Click to switch, your whole workspace in one window.
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

        {/* ---------------- SHOWCASE: summarize ---------------- */}
        <section id="summarize" className="showcase">
          <div className="wrap show-row rev">
            <div className="show-copy">
              <span className="kicker">Summaries</span>
              <h2 className="display">Read 500 lines in 5 seconds.</h2>
              <p>
                Select any wall of terminal output — a failing build, a noisy
                stack trace, a long test run — and Liftoff distills it to the one
                thing that matters: did it pass, what broke, and what to do next.
              </p>
              <div className="pwr">
                <div className="pwr-row">
                  <span className="pwr-chip pwr-chip--accent">gpt-oss-120b</span>
                  <span className="pwr-x">on</span>
                  <span className="pwr-chip">Cerebras</span>
                  <span className="pwr-tag">fastest inference available</span>
                </div>
                <p className="pwr-note">
                  Summaries land almost before you blink. <b>Bring your own key</b> —
                  it&apos;s stored in your macOS Keychain, and requests go straight
                  to Cerebras, <b>never through us</b>.
                </p>
              </div>
              <a href={DOWNLOAD} className="show-link">Try it free <span className="arr">→</span></a>
            </div>
            <div className="show-visual">
              <Frame title="atlas-api — cargo test">
                <div className="m-sum">
                  <div className="m-sum-term">
                    {[
                      "   Compiling atlas-api v0.4.1",
                      "error[E0308]: mismatched types",
                      "  --> src/handlers/auth.rs:42:18",
                      "   |",
                      "42 |     verify(&token, claims)",
                      "   |            ^^^^^^ expected `&str`, found `String`",
                      "error: could not compile `atlas-api`",
                      "test result: FAILED. 0 passed; 1 failed",
                    ].map((l, i) => (
                      <span className={`m-sum-line${i === 5 ? " sel" : ""}${l.startsWith("error") ? " err" : ""}`} key={i}>{l}</span>
                    ))}
                  </div>
                  <div className="m-sum-card">
                    <span className="m-sum-badge">
                      <span className="m-sum-spark" /> Summary · 1.4s
                    </span>
                    <b className="m-sum-head">`cargo test` failed — type error at `auth.rs:42`.</b>
                    <ul className="m-sum-bul">
                      <li>expected <code>&amp;str</code>, found <code>String</code> → add <code>.as_str()</code></li>
                      <li>build aborted; 0 of 1 tests ran</li>
                    </ul>
                  </div>
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
              <h2 className="display">A command center for machines that build alongside you.</h2>
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

        {/* ---------------- SHOWCASE: Air (mobile) ---------------- */}
        <section id="air" className="showcase">
          <div className="wrap show-row">
            <div className="show-copy">
              <span className="kicker kicker-lg">Air</span>
              <h2 className="display">Your terminals, in your pocket.</h2>
              <p>
                Agents run for minutes — with Air you don&apos;t have to sit and
                watch. Mirror any terminal to your phone or a browser over your
                own network: live output, and type back from anywhere.
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
                Switch projects, spawn terminals, resize splits and summarize
                output without ever reaching for the mouse. The whole workflow is
                a chord away.
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
              <h2 className="display">No middlemen. No cloud.</h2>
              <p>
                Air never routes through our servers — because there are none.
                Your terminals stream directly between your devices over your own
                network. We can&apos;t see them, and neither can anyone else.
              </p>
            </div>
            <div className="priv-grid">
              <div className="priv-cell">
                <div className="mfeat-ico"><Icon d="M12 2 4 6v6c0 5 3.4 8.5 8 10 4.6-1.5 8-5 8-10V6l-8-4ZM9.5 12l1.8 1.8L15 10" /></div>
                <h4>Zero third-party servers</h4>
                <p>Pairing, mirroring and control all happen peer-to-peer on your LAN or VPN. Nothing is uploaded, logged, or relayed through us.</p>
              </div>
              <div className="priv-cell">
                <div className="mfeat-ico"><Icon d="M5 12a7 7 0 0 1 14 0M2 12h2m16 0h2M12 2v2M12 19v3M7 12a5 5 0 0 1 10 0M12 12h.01" /></div>
                <h4>Lift off from anywhere</h4>
                <p>Want access beyond your home network? Spin up a secured mesh VPN like Tailscale in minutes — then reach your Mac from anywhere, privately.</p>
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
              every Air session. No paywalls, no accounts, no tracking.
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
            <a href="#summarize">Summaries</a>
            <a href="#keyboard">Shortcuts</a>
            <a href="#air">Air</a>
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
