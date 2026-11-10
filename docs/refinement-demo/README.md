15-second FineText refinement demo, authored and rendered in Film Studio.

- Film: `/Users/qiweili/Movies/FineText.rxfilmstudio`
- Composition: `0B70EBC9-A1C0-4A7E-B8A2-F9D6EAE24B24`
- Sequence: `72B2F927-E4DA-42FB-B4CE-997CEA70BA26` (`FineText — Refinement · 15s`)
- Format: 1920 × 1080, 60 fps, 900 frames, H.264 MP4 with stereo AAC music.
- Deliverable: `FineText-Refinement-15s.mp4`, rendered from Film Studio and not kept in the repository. `film-render.json` records the current Film Studio render version and path.
- Verified: 15.000 seconds, 900 decoded frames, full decode without errors, no timeline picture gaps, and visual inspection of the final render. `contact-sheet.png` samples the finished MP4.

Companion music: `FineText-Gentle-Motion-15s.wav` and `FineText-Gentle-Motion-15s.mp3`. Generated in Film Studio with its instrumental setting, then cut to 15 seconds with a 50 ms opening fade and a 1.2-second ending fade. The WAV contains exactly 720,000 stereo sample frames at 48 kHz; both formats decode without errors. `music.json` records the generation source and finishing settings. The finished WAV is on A1 from 0 to 15 seconds at its normalized level. Sequence render v004 and the deliverable MP4 include this music.

The animation is a deterministic Remotion translation of the current SwiftUI implementation. It is not a screen recording. The video shows animated text on a plain dark background, with the actual FineText app icon, a FineText title, and the one-line subtitle “Make it sound like you.” Plain Before / After text controls indicate the selected version and briefly show a pointer at each replay. The ending displays the app icon, FineText, and `fintext.app` (the website domain configured in the repository). The native reading surface is enlarged 3.65× for the video, with glyphs rasterized at 4× for sharp text.

`ExportLayout.swift` compiles with the production `FineText/Views/RefinementWordLayout.swift`. It exports TextKit glyph images and rectangles, occurrence-based word identities, original-to-refined categories, collision-aware relocation decisions in both directions, dark-appearance system colors, the production phase durations, and sampled native `UnitCurve` / `Spring.smooth` values. `Composition.tsx` mirrors `AnimatedRefinementText.present()` and `WordCanvas` for geometry, tint, opacity, highlight width, deletion strike width, squared insertion fade, line-wrap softening and final cleanup. Browser text layout is not used for the animated words.

| SwiftUI phase | Duration | Video behavior |
| --- | ---: | --- |
| prepare | 0.034 s | Categorize outgoing words |
| mark | 0.280 s | Ease-in-out highlight and red strike |
| fade | 0.160 s | Ease-out outgoing and collision-crossing words |
| stage | 0.034 s | Relocate hidden words and stage insertions |
| morph | 0.520 s | Native smooth spring; coordinated reflow and reveal |
| hold | 0.200 s | Hold comparison colors |
| cleanup | 0.240 s | Ease-out marks and restore plain text |

Each playback uses the nominal 1.468-second production schedule. Real app playback may shorten phases when layout preparation approaches its 1.9-second deadline; this deterministic export has no model, streaming or scheduling delays. Sampling at 60 fps quantizes phase boundaries to the movie frame clock.

| Movie time | Action |
| --- | --- |
| 0–2 s | Original draft reading hold |
| 2–3.468 s | Forward refinement |
| 3.468–6.5 s | Clean refined text |
| 6.5–7.968 s | Before-view replay |
| 7.968–10.5 s | Clean original text |
| 10.5–11.968 s | Forward refinement replay |
| 11.968–12.6 s | Clean refined text hold |
| 12.6–13 s | Crossfade to the closing screen |
| 13–15 s | FineText icon, title and website |

Regenerate native layout data from the repository root:

```sh
swiftc -module-cache-path /tmp/finetext-demo-module-cache \
  FineText/Views/RefinementWordLayout.swift \
  docs/refinement-demo/ExportLayout.swift -o /tmp/finetext-demo-export
/tmp/finetext-demo-export docs/refinement-demo/layout.json
```

Write `layout.json` and `Composition.tsx` to the composition's `src/` folder using Film Studio's `remotion_write_file` tools. Attach `app-icon.png` with `remotion_add_image` and use its returned `static_path` in the composition, then render the sequence with `sequence_render`. The app icon was exported from the installed FineText app's `AppIcon.icns`. The small viewport adaptation keeps Film Studio's thumbnail screenshots and full-resolution export in the same coordinate system.

Production source SHA-256 at authoring:

```text
55afbabca73e8299fd98aa72fe43b6c1c91d69bee2d44d610d362a050e2bc765  AnimatedRefinementText.swift
358f36313054fecfcc046eb76c4ba0cf0228531e9a62698ea09e5c8db5f02990  RefinementWordLayout.swift
```
