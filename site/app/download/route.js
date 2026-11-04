import fs from "node:fs";
import path from "node:path";

// Resolve at build time from the signed feed deployed with this website.
// GitHub's cached latest-release API can lag behind a newly published release.
export const dynamic = "force-static";

const FALLBACK = "https://github.com/shostkevych/liftoff/releases/latest";

export function GET() {
  let url = FALLBACK;
  try {
    const feed = fs.readFileSync(path.join(process.cwd(), "public", "appcast.xml"), "utf8");
    const version = feed.match(/<sparkle:shortVersionString>(\d+(?:\.\d+)*)<\/sparkle:shortVersionString>/)?.[1];
    if (version) {
      url = `https://github.com/shostkevych/liftoff/releases/download/v${version}/Liftoff-${version}.dmg`;
    }
  } catch {
    // Keep downloads available through GitHub if release metadata is missing.
  }
  return new Response(null, {
    status: 302,
    headers: { Location: url, "Cache-Control": "no-store" },
  });
}
