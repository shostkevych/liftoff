import fs from "node:fs";
import path from "node:path";
import LegalShell from "../components/LegalShell";

export const metadata = {
  title: "Changelog — Liftoff",
  description: "What's new in each Liftoff release.",
};

// Prerendered at build time — changelog.md is read from the site source dir,
// which only exists in the builder stage of the Docker image.
export const dynamic = "force-static";

/* Parse CHANGELOG.md: "## <version>" sections with "- " bullets. The intro
   paragraph above the first section is maintainer notes — skipped. */
function parseChangelog(md) {
  const sections = [];
  let current = null;
  for (const line of md.split("\n")) {
    if (line.startsWith("## ")) {
      current = { version: line.slice(3).trim(), items: [] };
      sections.push(current);
      continue;
    }
    if (current && line.trim().startsWith("- ")) {
      current.items.push(line.trim().slice(2));
    }
  }
  return sections;
}

/* Inline markdown: `code` and **bold**. */
function Inline({ text }) {
  return text.split(/(`[^`]+`|\*\*[^*]+\*\*)/).map((part, i) => {
    if (part.startsWith("`")) return <code key={i} className="mono">{part.slice(1, -1)}</code>;
    if (part.startsWith("**")) return <strong key={i}>{part.slice(2, -2)}</strong>;
    return part;
  });
}

export default function Changelog() {
  const md = fs.readFileSync(path.join(process.cwd(), "changelog.md"), "utf8");
  const releases = parseChangelog(md);

  return (
    <LegalShell
      tag="Changelog"
      title="What's new in Liftoff."
      intro="Every release, newest first. The same notes show up in the app's update prompt and post-update What's New popup."
    >
      {releases.map((r) => (
        <section key={r.version}>
          <h2><span className="num">v</span>{r.version}</h2>
          <ul>
            {r.items.map((item, i) => (
              <li key={i}><Inline text={item} /></li>
            ))}
          </ul>
        </section>
      ))}
    </LegalShell>
  );
}
