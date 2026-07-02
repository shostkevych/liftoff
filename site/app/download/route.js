import { readdir } from "node:fs/promises";
import path from "node:path";

// Stable download endpoint: always 302s to the newest signed/notarized .dmg in
// public/dmg, so links never need editing when a new version ships. DMGs live in
// their own dir (NOT public/releases) so Sparkle's generate_appcast — which scans
// releases/ — never sees a .dmg + .zip for the same version and errors on the dupe.
// The Sparkle auto-update feed keeps using the .zip enclosures in appcast.xml.
export const dynamic = "force-dynamic";

const FALLBACK = "https://liftoff.shostkevych.com/";

// Compare "1.10" > "1.9" numerically, segment by segment.
function cmpVersion(a, b) {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d) return d;
  }
  return 0;
}

export async function GET() {
  try {
    const dir = path.join(process.cwd(), "public", "dmg");
    const files = await readdir(dir);
    let best = null;
    for (const f of files) {
      const m = f.match(/^Liftoff-(\d+(?:\.\d+)*)\.dmg$/);
      if (!m) continue;
      if (!best || cmpVersion(m[1], best.ver) > 0) best = { file: f, ver: m[1] };
    }
    if (!best) return Response.redirect(FALLBACK, 302);
    return Response.redirect(
      `https://liftoff.shostkevych.com/dmg/${best.file}`,
      302
    );
  } catch {
    return Response.redirect(FALLBACK, 302);
  }
}
