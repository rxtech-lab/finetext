# FineText deep links

The macOS app accepts these navigation links, including when launched from a browser:

| URL | Destination |
| --- | --- |
| `finetext://rewrite` | Rewrite workspace window, preserving the current draft |
| `finetext://settings` | General settings |
| `finetext://settings/<tab>` | Settings tab: `general`, `platforms`, `providers`, `agents`, `flowcy`, `local`, `humanizer`, or `mcp` |
| `finetext://settings/local/hugging-face` | Local Models with the Hugging Face browser sheet |

Each tutorial's localized **Open in FineText** link uses the matching destination.
FineText must be installed with this feature; the website does not automatically
launch the app or detect installation. Browsers may ask before opening an app.
Unknown routes and links containing credentials, ports, queries, or fragments are
ignored. Links do not submit text, start downloads, or sign in. The existing
`finetext://oauth-callback` remains reserved for the authentication session.

Run parser checks with `bash scripts/test-deep-links.sh`, and tutorial checks with
`cd website && PLAYWRIGHT_CHANNEL=chrome bunx playwright test tests/tutorials.spec.ts`.

For manual checks, open each URL from a browser with the app closed, then repeat
with Settings already open on a different tab. Close the model browser sheet
and reopen its URL to check repeated presentation.
