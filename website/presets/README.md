# Rewrite presets

Every rewrite preset in the FineText app's **Add Platform** menu is a Markdown file in this directory. The website serves them as one JSON catalog at `/api/presets`, built during deployment. The app checks for a new catalog every 4 hours. It caches the last good copy for offline use, and a bundled copy covers the first launch.

## Menus

A directory is a menu, and menus can nest to any depth (submenu, sub-submenu, and so on). An optional `_menu.md` sets the menu's title, symbol and position:

```md
---
title:
  en: "Email"
  zh-CN: "电子邮件"
symbol: envelope   # SF Symbol
order: 60          # lower comes first; default 1000, then file name
---
```

Without `_menu.md`, the directory name is the title. Empty directories are skipped. This file (`README.md`) is ignored.

## Presets

Any other `.md` file is a preset. The front matter describes it, and the body is the platform guideline template that goes into the model's system prompt.

```md
---
id: emailSend                # stable and unique; history and per-preset tones use it, so never rename it
title: { en: "Send", zh-TW: "寄送" }   # text, or locale → text with "en" required
promptTitle: Email Send      # English name used in prompts (default: title.en)
symbol: envelope
kind: rewrite                # rewrite (default) or grammar, see below
tone: professional           # default tone: natural, professional, casual, witty, friendly,
                             # enthusiastic, informative, storytelling, bold, concise, empathetic
characterLimit: 280          # optional soft limit shown in the editor
order: 10
fields:                      # optional structured output, one text box with its own copy button per field
  - id: subject
    label: { en: "Subject" }
  - id: body
    multiline: true
    characterLimit: 5000     # optional
    label: { en: "Body" }
---
- Guidelines for the model…
```

The app shows a preset as the menu path joined with `·`, such as `Email · Send`.

With `fields`, the app tells the model to wrap each field in an XML tag (`<subject>…</subject>`). Each field then gets its own text box and copy button. Don't describe the layout (such as "start with a Subject: line") in the guidelines.

## Grammar presets

With `kind: grammar`, the app proofreads instead of rewriting. It asks the model to mark every correction inline and shows each one as the original word in red with a strike-through, then the replacement. Hovering a correction shows the explanation and alternative replacements, and the corrections can be hidden to read the clean text. Copying always copies the corrected text. Grammar presets skip humanization and can't have `fields`. The body holds the proofreading rules; the app adds the markup format itself.

Older apps that don't know `kind` treat a grammar preset as a normal rewrite with the same guidelines.

## Templates

The body uses a Jinja-style subset. The website and the app share one implementation spec (`src/lib/preset-template.ts`, `FineText/Services/PresetTemplate.swift`) and test cases (`src/lib/preset-template-cases.json`).

| Syntax | Meaning |
| --- | --- |
| `{{ tone }}` | Output a variable; missing values print nothing |
| `{% if character_limit %}…{% elif … %}…{% else %}…{% endif %}` | Conditionals |
| `{# note #}` | Comment |
| `{{- x -}}`, `{%- … -%}` | Trim whitespace on that side |
| `== != < <= > >= in and or not ( )` | Expressions |
| `upper lower capitalize title trim length default(x) replace(a, b)` | Filters, such as `{{ tone \| lower }}` |

A block tag on its own line does not leave a blank line behind.

Variables:

| Variable | Example |
| --- | --- |
| `tone` | `Witty` |
| `tone_id` | `witty` |
| `tone_guidance` | `clever and playful with light humor, never cringe` |
| `character_limit` | `280` (missing when the preset has none) |
| `preset.id`, `preset.title`, `preset.prompt_title` | `x`, `X · Post`, `X Post` |
| `app_language` | the app's interface language: `en`, `zh-CN`, `zh-HK`, `zh-TW` |

An unknown variable, an unknown filter or a syntax error fails `bun run test` and the website build.

## Publishing

1. Edit the files here.
2. Run `bun run test`.
3. Run `bun run presets:export` to refresh the copy bundled with the app (`FineText/Resources/presets.json`). The tests fail if it is stale.
4. Deploy the website. Apps pick up the new catalog within 4 hours, or right away with **Settings → General → Presets → Update Now**.
