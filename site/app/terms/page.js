import LegalShell from "../components/LegalShell";

const GITHUB = "https://github.com/yourname/liftoff";
const CONTACT = "personal@shostkevych.com";

export const metadata = {
  title: "Terms of Use — Liftoff",
  description:
    "The terms governing your use of Liftoff, a free and open-source macOS terminal licensed under the MIT License.",
};

export default function Terms() {
  return (
    <LegalShell
      tag="Terms of Use"
      title="Free, open, and as-is."
      updated="June 16, 2026"
      intro="Liftoff is free and open-source software, distributed under the MIT License. These terms explain the basis on which you may use the app, the website, and the Liftoff Air companion. By downloading or using Liftoff, you agree to them."
    >
      <h2><span className="num">1</span>The software is open source</h2>
      <p>
        Liftoff — including the macOS app, its terminal core, and the iOS companion — is
        released under the <strong>MIT License</strong>. That license is the primary
        agreement governing your rights to use, copy, modify, and distribute the software.
        You can read the full text in the{" "}
        <a className="inline" href={GITHUB} target="_blank" rel="noreferrer">project repository</a>.
        Where these terms and the MIT License differ regarding the software itself, the MIT
        License controls.
      </p>

      <h2><span className="num">2</span>No warranty</h2>
      <p>
        Liftoff is provided <strong>"as is", without warranty of any kind</strong>, express
        or implied, including but not limited to the warranties of merchantability, fitness
        for a particular purpose, and non-infringement. We do not warrant that the software
        will be error-free, uninterrupted, or secure for any particular use.
      </p>

      <h2><span className="num">3</span>Limitation of liability</h2>
      <p>
        To the fullest extent permitted by law, the authors and copyright holders of Liftoff
        shall not be liable for any claim, damages, data loss, or other liability — whether in
        an action of contract, tort, or otherwise — arising from, out of, or in connection
        with the software or your use of it. You run Liftoff, and any commands or agents inside
        it, at your own risk.
      </p>

      <h2><span className="num">4</span>Your responsibilities</h2>
      <p>When you use Liftoff, you agree that you are responsible for:</p>
      <ul>
        <li>The commands, scripts, and AI agents you choose to run inside the terminal.</li>
        <li>Keeping your paired devices and pairing QR code secure.</li>
        <li>Complying with the terms and laws that apply to any third-party tools, services, or AI providers you use through the app.</li>
        <li>Backing up your own work — Liftoff does not store or recover your data for you.</li>
      </ul>
      <p>
        You agree not to use Liftoff for any unlawful purpose or in any way that infringes the
        rights of others.
      </p>

      <h2><span className="num">5</span>Third-party tools and agents</h2>
      <p>
        Liftoff lets you run independent third-party software — shells, command-line tools, and
        AI coding agents such as Claude Code, Codex, and Gemini. These are not part of Liftoff,
        are not provided or controlled by us, and are governed by their own licenses and terms.
        We make no representations about them and are not responsible for their behavior, output,
        cost, or availability.
      </p>

      <h2><span className="num">6</span>Trademarks</h2>
      <p>
        The MIT License grants broad rights to the code. It does not grant rights to use the
        "Liftoff" name or logo in a way that implies endorsement. Product and company names
        referenced on this site (such as Claude Code, Codex, Gemini, and Tailscale) are
        trademarks of their respective owners and are used for identification only.
      </p>

      <h2><span className="num">7</span>Changes to these terms</h2>
      <p>
        We may update these terms from time to time. Updates will be posted here with a new
        "last updated" date, and the history remains visible in the open-source repository.
        Continued use of Liftoff after a change means you accept the revised terms.
      </p>

      <h2><span className="num">8</span>Contact</h2>
      <p>
        Questions about these terms? Reach out at{" "}
        <a className="inline mono" href={`mailto:${CONTACT}`}>{CONTACT}</a>{" "}
        or open an issue on{" "}
        <a className="inline" href={GITHUB} target="_blank" rel="noreferrer">GitHub</a>.
      </p>
    </LegalShell>
  );
}
