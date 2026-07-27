import LegalShell from "../components/LegalShell";

const GITHUB = "https://github.com/shostkevych/liftoff";
const CONTACT = "personal@shostkevych.com";

export const metadata = {
  title: "Privacy Policy — Liftoff",
  description:
    "Liftoff collects limited anonymous usage counts but never terminal content, commands, project paths, or personal data.",
};

export default function Privacy() {
  return (
    <LegalShell
      tag="Privacy Policy"
      title="Your terminals stay yours."
      updated="July 27, 2026"
      intro="Liftoff is a free, open-source macOS terminal. Terminal content and project data stay under your control. We collect only a few anonymous product counters so we can understand adoption and supported versions."
    >
      <h2><span className="num">1</span>The short version</h2>
      <ul>
        <li><strong>No account.</strong> Liftoff never asks you to sign up or log in.</li>
        <li><strong>Anonymous product metrics only.</strong> The app reports its version, an anonymous installation identifier, a last-seen heartbeat, and how many terminals were opened.</li>
        <li><strong>No sensitive data.</strong> We never collect terminal output, commands, prompts, project paths, filenames, user or device names, hardware details, or crash reports.</li>
        <li><strong>Everything is local.</strong> Your projects, terminal output, settings, and pairings live on your own devices.</li>
      </ul>

      <h2><span className="num">2</span>What Liftoff stores on your device</h2>
      <p>
        To work as a terminal and project workspace, Liftoff keeps the following
        on your Mac (and, for the companion, your phone):
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

      <h2><span className="num">3</span>Anonymous product metrics</h2>
      <p>
        Liftoff sends a small heartbeat when it starts and periodically while it is
        running. It contains a randomly generated installation identifier, the installed
        Liftoff version, and a batched count of terminals opened since the previous
        successful heartbeat.
      </p>
      <ul>
        <li>The random identifier is not derived from your Apple ID, name, email, hardware, network address, or any device identifier.</li>
        <li>The server stores only a one-way hash of that random identifier.</li>
        <li>Network addresses are not stored in the analytics database or shown in the dashboard.</li>
        <li>The counters are used only to measure active installations, version adoption, and aggregate terminal usage.</li>
      </ul>

      <h2><span className="num">4</span>Liftoff Air &amp; the web client</h2>
      <p>
        Liftoff Air mirrors a terminal to the iOS companion app or to a browser. This
        connection uses a direct path on your local network when available and an
        <strong>end-to-end encrypted relay</strong> for remote access. Terminal content is
        encrypted on one device and decrypted only on the paired device.
      </p>
      <ul>
        <li>The relay only forwards opaque encrypted frames. It cannot read terminal output, commands, or session content, and it never receives your encryption key.</li>
        <li>Pairing is established by scanning a QR code and protected with a passcode (and Face ID on iOS).</li>
        <li>The relay necessarily processes limited routing metadata such as session identifiers, connection timing, traffic sizes, and network addresses.</li>
      </ul>

      <h2><span className="num">5</span>Third-party AI agents</h2>
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

      <h2><span className="num">6</span>This website</h2>
      <p>
        The Liftoff marketing website sets no tracking cookies and runs no advertising or
        analytics scripts. Like virtually all web hosting, the provider serving this site
        may keep standard, short-lived server logs (such as IP addresses and requested
        URLs) for security and reliability. These logs are not used to identify or profile you.
      </p>

      <h2><span className="num">7</span>Children</h2>
      <p>
        Liftoff is a developer tool and is not directed at children. We do not knowingly
        collect personal information from anyone, including children.
      </p>

      <h2><span className="num">8</span>Changes to this policy</h2>
      <p>
        If this policy changes, the updated version will be published here with a new
        "last updated" date. Because Liftoff is open source, you can also review the
        full history of this page in the{" "}
        <a className="inline" href={GITHUB} target="_blank" rel="noreferrer">project repository</a>.
      </p>

      <h2><span className="num">9</span>Contact</h2>
      <p>
        Questions about privacy? Reach out at{" "}
        <a className="inline mono" href={`mailto:${CONTACT}`}>{CONTACT}</a>{" "}
        or open an issue on{" "}
        <a className="inline" href={GITHUB} target="_blank" rel="noreferrer">GitHub</a>.
      </p>
    </LegalShell>
  );
}
