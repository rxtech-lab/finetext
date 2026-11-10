import { buildPresetCatalog } from "@/lib/presets";

// Built once per deployment from website/presets/**/*.md and served from the CDN.
// The macOS app polls this every few hours and keeps the last good copy for offline use.
export const dynamic = "force-static";

export function GET() {
  const catalog = buildPresetCatalog();
  return Response.json(catalog, {
    headers: {
      "Cache-Control": "public, max-age=300, s-maxage=3600, stale-while-revalidate=86400",
      ETag: `"${catalog.version}"`,
    },
  });
}
