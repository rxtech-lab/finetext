// Writes the catalog bundled into the macOS app as the first-launch/offline fallback.
// Run after editing website/presets: `bun run presets:export`.
import { writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildPresetCatalog } from "../src/lib/presets";

const bundledCatalogPath = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "FineText", "Resources", "presets.json");
const catalog = buildPresetCatalog();
writeFileSync(bundledCatalogPath, JSON.stringify(catalog, null, 2) + "\n");
console.log(`Exported preset catalog ${catalog.version} to ${bundledCatalogPath}`);
