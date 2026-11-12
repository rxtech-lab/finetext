import { createHash } from "node:crypto";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { parse as parseYAML } from "yaml";
import { parseTemplate, templateVariables } from "./preset-template";

// Rewrite presets live as Markdown files under website/presets. A directory is a menu
// (optionally described by `_menu.md`), and any other `.md` file is a preset whose body is
// a Jinja-style template for the platform guidelines. Menus nest to any depth.

export const PRESET_SCHEMA_VERSION = 1;
export const TONES = [
  "natural", "professional", "casual", "witty", "friendly", "enthusiastic",
  "informative", "storytelling", "bold", "concise", "empathetic",
] as const;
/** What the app does with a preset: rewrite the text, or proofread it and mark each correction inline. */
export const PRESET_KINDS = ["rewrite", "grammar"] as const;
/** Variables the app supplies when rendering a preset template. */
export const TEMPLATE_VARIABLES = [
  "tone", "tone_id", "tone_guidance", "character_limit",
  "preset.id", "preset.title", "preset.prompt_title", "app_language",
] as const;

export type LocalizedText = { en: string } & Record<string, string>;
export type PresetField = { id: string; label: LocalizedText; multiline: boolean; characterLimit?: number };
export type PresetMenu = { type: "menu"; id: string; title: LocalizedText; symbol?: string; children: PresetNode[] };
export type Preset = {
  type: "preset"; id: string; title: LocalizedText; promptTitle: string; symbol?: string;
  kind?: Exclude<(typeof PRESET_KINDS)[number], "rewrite">;
  targetLanguage?: string; allowedTargetLanguages?: string[];
  tone?: (typeof TONES)[number]; characterLimit?: number; fields?: PresetField[]; template: string;
};
export type PresetNode = PresetMenu | Preset;
export type PresetCatalog = { schemaVersion: number; version: string; items: PresetNode[] };

export const presetsDirectory = path.join(process.cwd(), "presets");

class PresetError extends Error {}

function frontMatter(file: string): { data: Record<string, unknown>; body: string } {
  const source = readFileSync(file, "utf8").replace(/\r\n/g, "\n");
  const match = /^---\n([\s\S]*?)\n---\n?([\s\S]*)$/.exec(source);
  if (!match) return { data: {}, body: source };
  const data = parseYAML(match[1]) ?? {};
  if (typeof data !== "object" || Array.isArray(data)) throw new PresetError(`${file}: front matter must be a mapping`);
  return { data: data as Record<string, unknown>, body: match[2] };
}

function localized(value: unknown, where: string): LocalizedText {
  if (typeof value === "string" && value.trim()) return { en: value.trim() };
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const entries = Object.entries(value).map(([key, text]) => {
      if (typeof text !== "string" || !text.trim()) throw new PresetError(`${where}: "${key}" must be non-empty text`);
      return [key, text.trim()] as const;
    });
    const result = Object.fromEntries(entries.sort(([a], [b]) => a.localeCompare(b)));
    if (!result.en) throw new PresetError(`${where}: an "en" title is required`);
    return result as LocalizedText;
  }
  throw new PresetError(`${where}: expected text or a map of locale to text`);
}

const optionalString = (value: unknown, where: string) => {
  if (value === undefined) return undefined;
  if (typeof value !== "string" || !value.trim()) throw new PresetError(`${where} must be non-empty text`);
  return value.trim();
};

const optionalLimit = (value: unknown, where: string) => {
  if (value === undefined || value === null) return undefined;
  if (!Number.isInteger(value) || (value as number) <= 0) throw new PresetError(`${where} must be a positive integer`);
  return value as number;
};

const order = (data: Record<string, unknown>) => (typeof data.order === "number" ? data.order : 1000);

function readPreset(file: string): { node: Preset; order: number } {
  const { data, body } = frontMatter(file);
  const id = optionalString(data.id, `${file}: id`);
  if (!id || !/^[A-Za-z][A-Za-z0-9_-]*$/.test(id)) throw new PresetError(`${file}: id must start with a letter and use letters, digits, - or _`);
  const title = localized(data.title, `${file}: title`);
  const tone = data.tone;
  if (tone !== undefined && !(TONES as readonly unknown[]).includes(tone)) throw new PresetError(`${file}: unknown tone "${tone}"`);
  const kind = data.kind ?? "rewrite";
  if (!(PRESET_KINDS as readonly unknown[]).includes(kind)) throw new PresetError(`${file}: unknown kind "${kind}"`);
  if (kind === "grammar" && data.fields !== undefined) throw new PresetError(`${file}: grammar presets cannot have fields`);
  const languageCode = (value: unknown, where: string): string => {
    const code = optionalString(value, where);
    if (!code) throw new PresetError(`${where} must be a BCP-47 language code`);
    try {
      if (Intl.getCanonicalLocales(code)[0] !== code) throw new Error();
    } catch { throw new PresetError(`${where} must be a canonical BCP-47 language code`); }
    return code;
  };
  const targetLanguage = data.targetLanguage === undefined ? undefined : languageCode(data.targetLanguage, `${file}: targetLanguage`);
  let allowedTargetLanguages: string[] | undefined;
  if (data.allowedTargetLanguages !== undefined) {
    if (!Array.isArray(data.allowedTargetLanguages) || !data.allowedTargetLanguages.length) {
      throw new PresetError(`${file}: allowedTargetLanguages must be a non-empty list`);
    }
    allowedTargetLanguages = data.allowedTargetLanguages.map((code) => languageCode(code, `${file}: allowedTargetLanguages`));
    if (new Set(allowedTargetLanguages).size !== allowedTargetLanguages.length) throw new PresetError(`${file}: duplicate language codes`);
    if (targetLanguage && !allowedTargetLanguages.includes(targetLanguage)) throw new PresetError(`${file}: targetLanguage must be allowed`);
  }
  const template = body.trim() + "\n";
  try {
    parseTemplate(template);
  } catch (error) {
    throw new PresetError(`${file}: ${(error as Error).message}`);
  }
  const unknown = templateVariables(template).filter((name) => !(TEMPLATE_VARIABLES as readonly string[]).includes(name));
  if (unknown.length) throw new PresetError(`${file}: unknown template variables ${unknown.join(", ")}`);
  let fields: PresetField[] | undefined;
  if (data.fields !== undefined) {
    if (!Array.isArray(data.fields) || !data.fields.length) throw new PresetError(`${file}: fields must be a non-empty list`);
    fields = data.fields.map((raw, index) => {
      const where = `${file}: fields[${index}]`;
      if (!raw || typeof raw !== "object") throw new PresetError(`${where} must be a mapping`);
      const field = raw as Record<string, unknown>;
      const fieldID = optionalString(field.id, `${where}.id`);
      if (!fieldID || !/^[a-z][a-z0-9_]*$/.test(fieldID)) throw new PresetError(`${where}.id must be lowercase letters, digits or _`);
      const result: PresetField = { id: fieldID, label: localized(field.label, `${where}.label`), multiline: field.multiline === true };
      const limit = optionalLimit(field.characterLimit, `${where}.characterLimit`);
      if (limit) result.characterLimit = limit;
      return result;
    });
    if (new Set(fields.map((field) => field.id)).size !== fields.length) throw new PresetError(`${file}: duplicate field ids`);
  }
  const node: Preset = { type: "preset", id, title, promptTitle: optionalString(data.promptTitle, `${file}: promptTitle`) ?? title.en, template };
  const symbol = optionalString(data.symbol, `${file}: symbol`);
  if (symbol) node.symbol = symbol;
  // Only non-default kinds are written, so rewrite presets keep their existing catalog shape.
  if (kind !== "rewrite") node.kind = kind as Preset["kind"];
  if (tone) node.tone = tone as Preset["tone"];
  const limit = optionalLimit(data.characterLimit, `${file}: characterLimit`);
  if (limit) node.characterLimit = limit;
  if (fields) node.fields = fields;
  if (targetLanguage) node.targetLanguage = targetLanguage;
  if (allowedTargetLanguages) node.allowedTargetLanguages = allowedTargetLanguages;
  return { node, order: order(data) };
}

function readMenu(directory: string, relative: string): { node: PresetMenu; order: number } | null {
  const meta = path.join(directory, "_menu.md");
  const data: Record<string, unknown> = statSync(meta, { throwIfNoEntry: false })?.isFile() ? frontMatter(meta).data : {};
  const children = readChildren(directory, relative);
  if (!children.length) return null;
  const node: PresetMenu = {
    type: "menu", id: relative, title: localized(data.title ?? path.basename(directory), `${meta}: title`), children,
  };
  const symbol = optionalString(data.symbol, `${meta}: symbol`);
  if (symbol) node.symbol = symbol;
  return { node, order: order(data) };
}

function readChildren(directory: string, relative: string): PresetNode[] {
  const entries = readdirSync(directory, { withFileTypes: true })
    .filter((entry) => !entry.name.startsWith(".") && entry.name !== "_menu.md" && entry.name !== "README.md");
  type Item = { node: PresetNode; order: number; name: string };
  const items = entries.flatMap((entry): Item[] => {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      const menu = readMenu(full, relative ? `${relative}/${entry.name}` : entry.name);
      return menu ? [{ ...menu, name: entry.name }] : [];
    }
    return entry.name.endsWith(".md") ? [{ ...readPreset(full), name: entry.name }] : [];
  });
  return items.sort((a, b) => a.order - b.order || a.name.localeCompare(b.name)).map((item) => item.node);
}

export function buildPresetCatalog(directory = presetsDirectory): PresetCatalog {
  const items = readChildren(directory, "");
  const ids = new Map<string, string>();
  const visit = (nodes: PresetNode[], trail: string) => {
    for (const node of nodes) {
      if (node.type === "menu") visit(node.children, `${trail}${node.id}/`);
      else if (ids.has(node.id)) throw new PresetError(`Duplicate preset id "${node.id}" in ${ids.get(node.id)} and ${trail}`);
      else ids.set(node.id, trail || "/");
    }
  };
  visit(items, "");
  if (!ids.size) throw new PresetError(`No presets found in ${directory}`);
  const version = createHash("sha256").update(JSON.stringify(items)).digest("hex").slice(0, 16);
  return { schemaVersion: PRESET_SCHEMA_VERSION, version, items };
}
