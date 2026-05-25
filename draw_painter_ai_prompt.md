# Draw Painter AI — Build Prompt

## Goal
Build a Flutter app (`yammopatinerapp`) that lets a user draw freehand on a canvas and uses an AI model to interpret, complete, restyle, or describe the drawing.

## Target Platforms
Android, iOS, macOS, Windows, Linux, Web (all six already scaffolded in this repo).

## Core User Flows
1. **Draw** — user draws on a full-screen canvas with finger/mouse/stylus.
2. **AI action** — user picks one of:
   - Describe the drawing (image → text)
   - Complete / continue the drawing (image → image)
   - Restyle the drawing (image + style prompt → image)
3. **Review** — show AI result side-by-side with the original; allow save / share / iterate.

## Drawing Surface — Requirements
- [ ] Pressure / stylus support where the platform exposes it.
- [ ] Tools: pen, eraser, color picker, stroke width, undo, redo, clear.
- [ ] Layer system (at minimum: drawing layer + AI-result layer).
- [ ] Export the canvas to PNG bytes for upload to the model.

## AI Integration
- **Provider:** TBD (Anthropic Claude for vision+describe; a separate image-gen provider for image→image — to be decided).
- **API key handling:** load from `--dart-define` at build time; never commit. Loader lives in a single `lib/config/` file.
- **Network layer:** one `AiClient` abstraction so the UI never talks to HTTP directly. Swap providers without touching widgets.
- **Failure modes to design for:** offline, rate-limited, content-policy refusal, timeout, partial response.

## Architecture Sketch
```
lib/
  main.dart                  # app entrypoint + routing
  app/                       # MaterialApp, theme, router
  features/
    canvas/                  # drawing surface, tools, stroke model
    ai/                      # AiClient, request/response models, prompt builders
    gallery/                 # saved drawings + AI results
  config/                    # env / api keys
  shared/                    # widgets, utils, theme tokens
```
State management: TBD (Riverpod or built-in `ChangeNotifier` — pick one and stay with it).

## Out of Scope (v1)
- Multi-user / accounts / cloud sync
- Real-time collaboration
- Video / animation export
- On-device model inference

## Open Questions
- [ ] Which image-generation provider? (Cost, latency, content policy all matter.)
- [ ] Do we render AI output back onto the canvas as an editable layer, or only as a static result image?
- [ ] Persistence: SQLite (`drift`/`sqflite`) vs. simple file-based JSON for v1?
- [ ] Style prompt UX — preset chips, free-text field, or both?

## Known Repo State
`lib/main.dart` is still the Flutter counter starter and currently has two syntax errors (`.fromSeed` line 31, `.center` line 105 missing their class prefixes). Fix or replace before any feature work.
