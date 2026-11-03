// Resolve the latest DMG without bundling application archives in the website.
// If GitHub's API is unavailable, its release page still provides the download.
export const dynamic = "force-dynamic";

const FALLBACK = "https://github.com/shostkevych/liftoff/releases/latest";
const GITHUB_LATEST =
  "https://api.github.com/repos/shostkevych/liftoff/releases/latest";

async function githubDmgUrl() {
  const res = await fetch(GITHUB_LATEST, {
    headers: { Accept: "application/vnd.github+json" },
    next: { revalidate: 300 },
    signal: AbortSignal.timeout(5000),
  });
  if (!res.ok) return null;
  const release = await res.json();
  const dmg = (release.assets || []).find((a) => a.name.endsWith(".dmg"));
  return dmg?.browser_download_url ?? null;
}

export async function GET() {
  const url = await githubDmgUrl().catch(() => null);
  return new Response(null, {
    status: 302,
    headers: { Location: url ?? FALLBACK, "Cache-Control": "no-store" },
  });
}
