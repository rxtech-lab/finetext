# FineText

![FineText illustration: one draft becomes polished writing, translations, and an image](docs/images/finetext-overview.png)

FineText is a native Mac menu bar app for polishing your words and creating visuals alongside them.

- **Rewrite** drafts for X, Reddit, LinkedIn, blog posts, and messages. Choose a tone or save your own reusable platform instructions.
- **Translate** original text or rewrites into multiple languages, with local TranslateGemma support.
- **Create images** with your choice of aspect ratio, art direction, and transparent backgrounds.
- **Choose your models:** connect an OpenAI-compatible provider, use your Codex or Claude Code setup, or download a local text model.

**[Visit fintext.app for downloads and more information →](https://fintext.app)**

## Platform presets

The platform presets in **Add Platform** are Markdown files in [`website/presets`](website/presets/README.md). Directories become menus, nested to any depth, and the preset bodies are Jinja-style templates. The website serves them at `/api/presets`. Debug builds read `http://localhost:3000/api/presets` (run `bun run dev` in `website/`), and Release builds read `https://fintext.app/api/presets`. The app checks every 4 hours and caches the last good catalog for offline use, with a bundled copy for first launch. Presets with `fields` (such as Email · Send and Reddit · Post) show each part in its own box with its own copy button. Run `python3 scripts/test-presets.py` to check the app's template renderer against the website's shared cases.

## MCP server

FineText runs a local [MCP](https://modelcontextprotocol.io) server so other apps can rewrite with it. Turn it on in **Settings → MCP** (on by default); it listens only on `127.0.0.1` at `http://127.0.0.1:47821/mcp` (the port is configurable). It uses the Streamable HTTP transport; tool calls stream progress notifications over SSE, and closing the connection cancels the call.

| Tool | What it does |
|---|---|
| `list_templates` | Cloud presets (menu paths flattened, with their fields) and your custom presets |
| `list_models` | Text models from your providers, Codex, Claude Code and local MLX models |
| `rewrite` | Writes a fresh draft with the agent and the template's guidelines, then runs the humanization loop and returns the text, fields and AI scores |
| `humanize` | Runs only the humanization loop on existing text |
| `score_text` | Scores text with the selected AI detector |

`rewrite` and `humanize` accept `text` or `fields`, `template_id`, `tone`, `model`, `instructions`, `context` (reference facts), `humanization` overrides (`mode`, `rounds`, `target_score`, `engine`) and `preserve_placeholders`, which keeps every `{{ … }}` placeholder and discards humanization rounds that lose one. MCP spend is recorded in the costs ledger under its own session. **Settings → MCP → View Request Log** lists every request with live progress and the full request and response. Connect Claude Code with `claude mcp add --transport http finetext http://127.0.0.1:47821/mcp`. [vc-email](https://github.com/sirily11/vc-email) uses this server for all of its rewriting.

Requires macOS 26 or later and Apple silicon.

This repository contains the SwiftUI macOS app in [`FineText/`](FineText/) and the Next.js website in [`website/`](website/).

*The image above is an AI-generated illustration of the workflow.*

For Claude Code, install with `brew install --cask claude-code`, run `claude auth login` in Terminal, then open **Settings → General → Claude Code** to detect the CLI. Claude Code uses your existing credentials and choice of model for rewriting and translation. The Codex and Claude Code submenus list models through [RxAgentSDK](https://github.com/rxtech-lab/RxAgentSDK); choose **CLI Default** to keep your CLI configuration.

For humanization, open **Settings → Humanizer → Translation model** and choose TranslateGemma or **Meta NLLB-200 600M**, then download the selected model in its sheet. NLLB runs entirely on this Mac through native ONNX Runtime Swift bindings with Swift tokenization; it needs no Python installation or API key. Its quantized ONNX weights download from [Xenova on Hugging Face](https://huggingface.co/Xenova/nllb-200-distilled-600M) (about 1.34 GB). Meta licenses [NLLB-200](https://huggingface.co/facebook/nllb-200-distilled-600M) under CC-BY-NC 4.0 for noncommercial use. The selected model is saved and used for humanizer round trips.

For AI scoring, open **Settings → Humanizer → AI detector**, choose **Desklib v1.01** (MIT) or **Tropa Mini** (Apache-2.0), and download its weights in the dedicated sheet. The detector needs Python 3.10–3.13; FineText installs its inference dependencies in a private environment on download. Scoring then runs offline on this Mac. Each detector download is about 1.75 GB, plus the shared inference runtime.

Choose **Automatic · target score** to check after every humanization round until the score is at or below your **Target AI score**. Automatic checking stops after three consecutive rounds without a lower best score, keeping the lowest-scoring completed result. Improving runs have no round limit; **Stop** also cancels the current work and keeps the best result. Choose translation round trips or the selected rewrite model as the humanization engine. Using a remote rewrite model can consume provider credits on every round. Fixed-round and off modes remain available, and can still score text with an enabled detector.

The result’s **AI score** opens a sheet with initial/final scores, the target, detector, and completed rounds. Editing the output hides its stale score. Scores describe detector confidence, not authorship or writing quality; these detectors only score English prose of at least 50 words. Short or unsupported text gets an explanation instead of a score.

While humanizing, the result previews each draft (including streamed rewrite output). The overlay labels the retained score as **Best AI score**, since the preview has not necessarily been scored yet. Completion or cancellation restores the best completed result. Automatic runs explain when they stop after three rounds without improvement; unchanged drafts count toward that limit without repeating detector inference. Rewrite rounds vary their editing focus while preserving the original facts.

Validate automatic checking and subprocess cancellation with `python3 scripts/test-humanization.py`. With the detector dependencies installed, `python3 scripts/test-detector-inference.py` tests real offline inference against tiny synthetic checkpoints; it does not benchmark detector accuracy.

### Animated GIF output

For GPT Image 2.6 Flare/Sunburst (including provider-prefixed model IDs) or Codex Image,
open **Output: Still image** and enable **Animated GIF**. The dedicated sheet controls
2–64 frames and 20–2000 ms per frame. Describe motion and looping in Art Direction.

FineText splits longer animations into up to four still sprite sheets (at most
16 frames per sheet), using each sheet’s final frame as a reference for the next.
It crops the cells in reading order and assembles one looping GIF
locally with native ImageIO. Each sheet is a separate billed image request; costs
are recorded separately. Requests use the normal still-image endpoint and do
not require native GIF support from the provider or Codex CLI. The prompt requests
consistent framing, progressive motion and a smooth loop; visual consistency
still depends on the model's generated grid. GIF mode uses an opaque background.

Previews animate, and copying/saving retains GIF bytes. Refinement uses a still
frame from the previous GIF as its reference and generates a fresh frame grid.
The original image and undo remain available if generation or assembly fails.

Run `python3 scripts/test-image-gif.py` to verify grid requests, cell order, timing,
looping metadata, Codex app-server integration and saved settings without paid
provider requests. Live model quality and UI playback require separate checks.
