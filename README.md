# FineText

![FineText illustration: one draft becomes polished writing, translations, and an image](docs/images/finetext-overview.png)

FineText is a native Mac menu bar app for polishing your words and creating visuals alongside them.

- **Rewrite** drafts for X, Reddit, LinkedIn, blog posts, and messages. Choose a tone or save your own reusable platform instructions.
- **Translate** original text or rewrites into multiple languages, with local TranslateGemma support.
- **Create images** with your choice of aspect ratio, art direction, and transparent backgrounds.
- **Choose your models:** connect an OpenAI-compatible provider, use your Codex or Claude Code setup, or download a local text model.

**[Visit fintext.app for downloads and more information →](https://fintext.app)**

Requires macOS 26 or later and Apple silicon.

This repository contains the SwiftUI macOS app in [`FineText/`](FineText/) and the Next.js website in [`website/`](website/).

*The image above is an AI-generated illustration of the workflow.*

For Claude Code, install with `brew install --cask claude-code`, run `claude auth login` in Terminal, then open **Settings → General → Claude Code** to detect the CLI. Claude Code uses your existing credentials and choice of model for rewriting and translation. The Codex and Claude Code submenus list models through [RxAgentSDK](https://github.com/rxtech-lab/RxAgentSDK); choose **CLI Default** to keep your CLI configuration.

For humanization, open **Settings → Humanizer → Translation model** and choose TranslateGemma or **Meta NLLB-200 600M**, then download the selected model in its sheet. NLLB runs entirely on this Mac through native ONNX Runtime Swift bindings with Swift tokenization; it needs no Python installation or API key. Its quantized ONNX weights download from [Xenova on Hugging Face](https://huggingface.co/Xenova/nllb-200-distilled-600M) (about 1.34 GB). Meta licenses [NLLB-200](https://huggingface.co/facebook/nllb-200-distilled-600M) under CC-BY-NC 4.0 for noncommercial use. The selected model is saved and used for humanizer round trips.

For AI scoring, open **Settings → Humanizer → AI detector**, choose **Desklib v1.01** (MIT) or **Tropa Mini** (Apache-2.0), and download its weights in the dedicated sheet. The detector needs Python 3.10–3.13; FineText installs its inference dependencies in a private environment on download. Scoring then runs offline on this Mac. Each detector download is about 1.75 GB, plus the shared inference runtime.

Choose **Automatic · target score** to check after every humanization round until the score is at or below your **Target AI score**. Automatic checking stops after three consecutive rounds without a lower best score, keeping the lowest-scoring completed result. Improving runs have no round limit; **Stop** also cancels the current work and keeps the best result. Choose translation round trips or the selected rewrite model as the humanization engine. Using a remote rewrite model can consume provider credits on every round. Fixed-round and off modes remain available, and can still score text with an enabled detector.

The result’s **AI score** opens a sheet with initial/final scores, the target, detector, and completed rounds. Editing the output hides its stale score. Scores describe detector confidence, not authorship or writing quality; these detectors only score English prose of at least 50 words. Short or unsupported text gets an explanation instead of a score.

Validate automatic checking and subprocess cancellation with `python3 scripts/test-humanization.py`. With the detector dependencies installed, `python3 scripts/test-detector-inference.py` tests real offline inference against tiny synthetic checkpoints; it does not benchmark detector accuracy.
