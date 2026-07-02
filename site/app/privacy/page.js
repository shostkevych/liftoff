import LegalShell from "../components/LegalShell";

const GITHUB = "https://github.com/yourname/liftoff";
const CONTACT = "personal@shostkevych.com";

export const metadata = {
  title: "Privacy Policy — Liftoff",
  description:
    "Liftoff collects no personal data, no telemetry, and runs no servers. Your terminals stay on your own devices and network.",
};

export default function Privacy() {
  return (
    <LegalShell
      tag="Privacy Policy"
      title="Your terminals stay yours."
      updated="June 16, 2026"
      intro="Liftoff is a free, open-source macOS terminal. It is built so that your data never leaves your control. We do not run servers, collect telemetry, or ask you to create an account. This policy explains, in plain terms, exactly what that means."
    >
      <h2><span className="num">1</span>The short version</h2>
      <ul>
        <li><strong>No account.</strong> Liftoff never asks you to sign up or log in.</li>
        <li><strong>No telemetry or analytics.</strong> The app does not phone home, track usage, or send crash reports automatically.</li>
        <li><strong>No servers.</strong> We operate no backend that your terminals, projects, or keystrokes pass through.</li>
        <li><strong>Everything is local.</strong> Your projects, terminal output, settings, and pairings live on your own devices.</li>
      </ul>

      <h2><span className="num">2</span>What Liftoff stores on your device</h2>
      <p>
        To work as a terminal and project workspace, Liftoff keeps the following
        on your Mac (and, for the companion, your phone). None of it is transmitted to us:
      </p>
      <ul>
        <li>Your application settings and preferences (themes, layouts, per-project accent colors).</li>
        <li>The list of projects and working directories you choose to open.</li>
        <li>Pairing information for Liftoff Air, used to reconnect your trusted devices.</li>
      </ul>
      <p>
        This data is stored locally using standard macOS and iOS mechanisms. You can
        remove it at any time by deleting the relevant project, clearing the app's
        settings, or uninstalling the app.
      </p>

      <h2><span className="num">3</span>Liftoff Air &amp; the web client</h2>
      <p>
        Liftoff Air mirrors a terminal to the iOS companion app or to a browser. This
        connection is <strong>peer-to-peer over your own network</strong> — your LAN, or a
        private mesh VPN such as Tailscale. Terminal output and the input you type travel
        directly between your devices.
      </p>
      <ul>
        <li>Nothing is uploaded to, logged by, or relayed through any server we operate — because there is none.</li>
        <li>Pairing is established by scanning a QR code and protected with a passcode (and Face ID on iOS).</li>
        <li>If you choose to enable remote access (e.g. via a VPN), the security of that network is managed by you and the VPN provider you select.</li>
      </ul>

      <h2><span className="num">4</span>Third-party AI agents</h2>
      <p>
        Liftoff is a terminal — it runs whatever commands and tools you launch inside it,
        including AI coding agents such as Claude Code, Codex, Gemini, opencode, Aider, and
        others. When you use one of these agents, your prompts and code may be sent by that
        agent to its own provider, subject to that provider's privacy policy and terms.
      </p>
      <p>
        Liftoff does not control, intercept, or process that traffic, and we have no
        relationship with those providers. Please review the privacy practices of any AI
        agent or service you run inside Liftoff.
      </p>

      <h2><span className="num">5</span>This website</h2>
      <p>
        The Liftoff marketing website sets no tracking cookies and runs no advertising or
        analytics scripts. Like virtually all web hosting, the provider serving this site
        may keep standard, short-lived server logs (such as IP addresses and requested
        URLs) for security and reliability. These logs are not used to identify or profile you.
      </p>

      <h2><span className="num">6</span>Children</h2>
      <p>
        Liftoff is a developer tool and is not directed at children. We do not knowingly
        collect personal information from anyone, including children.
      </p>

      <h2><span className="num">7</span>Changes to this policy</h2>
      <p>
        If this policy changes, the updated version will be published here with a new
        "last updated" date. Because Liftoff is open source, you can also review the
        full history of this page in the{" "}
        <a className="inline" href={GITHUB} target="_blank" rel="noreferrer">project repository</a>.
      </p>

      <h2><span className="num">8</span>Contact</h2>
      <p>
        Questions about privacy? Reach out at{" "}
        <a className="inline mono" href={`mailto:${CONTACT}`}>{CONTACT}</a>{" "}
        or open an issue on{" "}
        <a className="inline" href={GITHUB} target="_blank" rel="noreferrer">GitHub</a>.
      </p>
    </LegalShell>
  );
}
