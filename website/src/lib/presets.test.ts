import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import cases from "./preset-template-cases.json";
import { renderTemplate, type TemplateValue, templateVariables } from "./preset-template";
import { buildPresetCatalog, type Preset, type PresetMenu, type PresetNode, presetsDirectory } from "./presets";

describe("preset templates", () => {
  for (const item of cases.render) {
    test(item.name, () => {
      assert.equal(renderTemplate(item.template, item.context as Record<string, TemplateValue>), item.expected);
    });
  }
  for (const item of cases.errors) {
    test(`rejects ${item.name}`, () => {
      assert.throws(() => renderTemplate(item.template, {}));
    });
  }
  test("lists variables in every branch", () => {
    assert.deepEqual(templateVariables("{% if a %}{{ b.c | default(d) }}{% else %}{{ e }}{% endif %}"), ["a", "b.c", "d", "e"]);
  });
});

function fixture(files: Record<string, string>) {
  const root = mkdtempSync(path.join(tmpdir(), "presets-"));
  for (const [name, content] of Object.entries(files)) {
    mkdirSync(path.dirname(path.join(root, name)), { recursive: true });
    writeFileSync(path.join(root, name), content);
  }
  return root;
}

const preset = (id: string, extra = "", body = "- Be brief.") => `---\nid: ${id}\ntitle: ${id}\n${extra}---\n${body}\n`;

describe("preset catalog", () => {
  test("nests menus to any depth and orders them", () => {
    const root = fixture({
      "b.md": preset("b", "order: 2\n"),
      "a/_menu.md": "---\ntitle:\n  en: Social\n  zh-TW: 社群\nsymbol: star\norder: 1\n---\n",
      "a/deep/deeper/leaf.md": preset("leaf"),
      "a/top.md": preset("top"),
      "empty/.keep": "",
      "README.md": "ignored",
    });
    const catalog = buildPresetCatalog(root);
    assert.equal(catalog.items.length, 2);
    const [menu, leaf] = catalog.items as [PresetMenu, Preset];
    assert.deepEqual([menu.type, menu.id, menu.title, menu.symbol], ["menu", "a", { en: "Social", "zh-TW": "社群" }, "star"]);
    assert.deepEqual([leaf.type, leaf.id], ["preset", "b"]);
    const deep = menu.children[0] as PresetMenu;
    assert.deepEqual([deep.id, deep.title], ["a/deep", { en: "deep" }]);
    const deepest = (deep.children[0] as PresetMenu).children[0] as Preset;
    assert.deepEqual([deepest.id, deepest.promptTitle], ["leaf", "leaf"]);
    assert.equal((menu.children[1] as Preset).id, "top");
    assert.match(catalog.version, /^[0-9a-f]{16}$/);
    assert.equal(buildPresetCatalog(root).version, catalog.version);
  });

  test("parses fields, tone and limits", () => {
    const [item] = buildPresetCatalog(fixture({
      "mail.md": preset("mail", "tone: professional\ncharacterLimit: 99\nfields:\n  - id: subject\n    label: Subject\n  - id: body\n    multiline: true\n    label: Body\n"),
    })).items as [Preset];
    assert.equal(item.tone, "professional");
    assert.equal(item.characterLimit, 99);
    assert.deepEqual(item.fields, [
      { id: "subject", label: { en: "Subject" }, multiline: false },
      { id: "body", label: { en: "Body" }, multiline: true },
    ]);
  });

  test("parses the grammar kind and omits the default", () => {
    const items = buildPresetCatalog(fixture({
      "fix.md": preset("fix", "kind: grammar\norder: 1\n"),
      "post.md": preset("post", "kind: rewrite\norder: 2\n"),
    })).items as [Preset, Preset];
    assert.equal(items[0].kind, "grammar");
    assert.equal("kind" in items[1], false);
  });

  const invalid: [string, Record<string, string>][] = [
    ["duplicate ids", { "a.md": preset("same"), "b/c.md": preset("same") }],
    ["unknown variables", { "a.md": preset("a", "", "{{ tonne }}") }],
    ["template syntax", { "a.md": preset("a", "", "{% if tone %}") }],
    ["unknown tone", { "a.md": preset("a", "tone: shouty\n") }],
    ["missing id", { "a.md": "---\ntitle: A\n---\nx" }],
    ["missing English title", { "a.md": "---\nid: a\ntitle:\n  zh-TW: 甲\n---\nx" }],
    ["bad field id", { "a.md": preset("a", "fields:\n  - id: Bad Field\n    label: X\n") }],
    ["unknown kind", { "a.md": preset("a", "kind: poetry\n") }],
    ["grammar with fields", { "a.md": preset("a", "kind: grammar\nfields:\n  - id: body\n    label: Body\n") }],
    ["no presets", { "README.md": "x" }],
  ];
  for (const [name, files] of invalid) {
    test(`rejects ${name}`, () => {
      assert.throws(() => buildPresetCatalog(fixture(files)));
    });
  }

  test("published presets keep the app's existing ids", () => {
    const ids: string[] = [];
    const visit = (nodes: PresetNode[]) => nodes.forEach((node) => (node.type === "menu" ? visit(node.children) : ids.push(node.id)));
    visit(buildPresetCatalog().items);
    assert.deepEqual(ids.sort(), [
      "blog", "cantonese", "emailReply", "emailSend", "grammar", "linkedin", "linkedinChat", "linkedinComment", "message",
      "productHunt", "productHuntComment", "productHuntDescription", "productHuntMakerComment", "productHuntReply",
      "productHuntTagline", "reddit", "redditComment", "x", "xReply", "xThread",
      "youtubeComment", "youtubeDescription", "youtubeTitle",
    ].sort());
  });

  test("the catalog bundled in the app is up to date (run `bun run presets:export`)", () => {
    const bundled = JSON.parse(readFileSync(path.join(presetsDirectory, "..", "..", "FineText", "Resources", "presets.json"), "utf8"));
    assert.deepEqual(bundled, buildPresetCatalog());
  });
});
