# Even — design language

Source of truth: the Claude Design projects (claude.ai/design)
- **"Even — Couple's house manager"** — main app design explorations
- Project `b15c92d8-126e-4255-bca8-b984b7775b99`, file **Even Play.dc.html**
  (playful iteration) — exported here as [`even-play.dc.html`](even-play.dc.html).
  Note: the `.dc.html` file is a Claude Design runtime document (needs its
  `support.js`); treat it as a readable spec, not a standalone page.

## Tokens (extracted 2026-07-15, used by the live coming-soon page)

| Role | Value |
|---|---|
| Paper ground | `#E9E1D2` |
| Paper raised | `#F6F1E6` / `#FBF7EE` |
| Espresso ink | `#26201A` (deep: `#211B15`) |
| Terracotta accent | `#A6552F` / `#A0522D`, hover `#7A3A1D` |
| Pine pop | `#37756D` |
| Stone / taupe neutrals | `#8A7D69`, `#B8AC99` |
| Display serif | **Newsreader** (italic for emphasis) |
| Body sans | **Source Sans 3** |

Texture: subtle paper grain (SVG `feTurbulence`). Motion: soft "settle/drop"
entrances; things gently land rather than fade. Voice: warm, ritual-based —
"the weekly reset", "running balance", "say one kind thing" — never cold fintech.

## Live surfaces

- **thisiseven.app** — coming-soon page (`web/coming-soon/`), Cloudflare Pages
  project `thisiseven`. Deploy: see `web/coming-soon/` note in the root CLAUDE.md.
