# AR Creative — Workflow & Implementation Status

> Branch: `AR_Drawing`. This document captures everything built so far on top of the
> original "Draw Painter" app. It is a snapshot of the current working tree — most of
> the work below is not yet committed.

The app started as a single-screen freehand drawing app and has grown into a
**4-tab creative suite** (`AR Creative`) backed by Supabase. Each tab is an
independent feature with its own GetX controller(s) and screens, all sharing one
data layer (`svg_assets`) and one visual language (gradient + glass theme).

---

## 1. App shell & startup

**Entry:** `lib/main.dart`

```
main()
  ├─ WidgetsFlutterBinding.ensureInitialized()
  ├─ AuthService.ensureInitialized()      // no-op when SUPABASE_* env is absent
  ├─ Get.put(AuthService,  permanent: true)
  ├─ Get.put(SvgAssetService, permanent: true)
  ├─ Get.put(SavedDrawingService, permanent: true)
  └─ runApp(DrawPainterApp)                // GetMaterialApp, light/dark AppTheme
       └─ AuthGate
            ├─ backend NOT configured → HomeScreen   (fully usable offline)
            └─ backend configured     → Obx: signedIn ? HomeScreen : LoginScreen
```

**HomeScreen** is a `NavigationBar` over an `IndexedStack` (every tab stays mounted,
so in-progress drawings / puzzle progress survive tab switches):

| # | Tab        | Screen                  | Feature           |
|---|------------|-------------------------|-------------------|
| 0 | Painting   | `PaintingHomeScreen`    | Draw & color      |
| 1 | AR Drawing | `ArHomeScreen`          | Trace over camera |
| 2 | Puzzle     | `JigsawPuzzleScreen`    | Jigsaw puzzle     |
| 3 | Account    | `AccountScreen`         | Auth / profile    |

---

## 2. Feature workflow: Painting & Coloring (Tab 0)

**Flow:** `PaintingHomeScreen` → pick activity → `PaintingCanvasScreen` → draw/color → save → `SavedDrawingScreen`

- **Activity picker** offers: **Free Draw** (blank canvas), **Upload SVG** (`file_picker`),
  and **Portal templates** streamed from Supabase `svg_assets` (`category = Painting`).
- **Coloring templates are SVG-based** with a region model:
  - `ColoringPageLoader` pipeline: `loadFromUrl()` (HTTP GET the asset's `public_url`)
    → `importRawSvg()` (parse regions + outline path-data) → `loadFromManifest()`
    (path-data → `dart:ui` Paths) → `flutter_svg` pre-render for a pixel-faithful line-art layer.
  - **Region clipping:** inner-first ordering, smallest-region-wins. The stroke's first
    point chooses the single region it is clipped to, so paint never bleeds between petals/wings.
- **Canvas tools** (top rail): Brush (Round/Soft/Marker/Pencil) · Eraser (`BlendMode.clear`
  in an isolated layer) · Fill (vector region fill or raster flood-fill) · Pick (eyedropper) ·
  Save. Bottom pill: undo / color / redo. Stroke widths: 2/6/12/20/32.
- **Coordinates** are stored in the template's viewBox/picture space so they survive canvas resize.
- **Undo/redo** snapshots the whole actions list at the start of each action (atomic per stroke/fill/clear).
- **Saving:** `DrawingController.renderCanvasPng()` (RepaintBoundary → PNG, `pixelRatio: 3.0`) →
  `SavedDrawingService.save()` uploads to Supabase Storage `<uid>/<timestamp>.png` and inserts a
  `saved_drawings` row. No backend/session → local PNG only (share-only flow).

**Key files:** `painting_home_screen.dart`, `painting_canvas_screen.dart`,
`saved_drawing_screen.dart`, `controllers/drawing_controller.dart`,
`coloring/coloring_page*.dart`, `coloring/parsing/*`, `widgets/painter.dart`,
`widgets/color_picker_sheet.dart`, `widgets/bottom_controls.dart`,
`models/stroke.dart`, `models/drawing_tool.dart`, `services/saved_drawing_service.dart`.

---

## 3. Feature workflow: AR Drawing (Tab 1)

**Flow:** `ArHomeScreen` (image chooser) → pick source → `ArDrawingScreen` (live camera) → trace by hand

- **What it does:** overlays a chosen image, centered over the **live camera feed** at
  adjustable opacity, so the user can hand-trace it over a real surface (paper).
- **Image sources:** Gallery photo (`image_picker`), local SVG (`file_picker`), or
  **Portal preset** from `svg_assets` (`category = Drawing`, watched via Realtime).
- **Overlay** (`ar_overlay_image.dart`) is draggable + scalable with a lock toggle to freeze it.
- **Camera** (`camera: ^0.12.0+1`) is lifecycle-aware (init on resume, release on pause);
  desktop / no-camera falls back to `CameraErrorWidget`. Controls: opacity slider, flip
  camera (≥2 cameras), torch/flashlight. Needs `NSCameraUsageDescription` (iOS).

**Key files:** `ar_home_screen.dart`, `ar_drawing_screen.dart`, `widgets/ar_overlay_image.dart`,
`widgets/camera_placeholder.dart`, `widgets/bottom_controls.dart`.

---

## 4. Feature workflow: Jigsaw Puzzle (Tab 2)

**Flow:** `JigsawPuzzleScreen` (setup) → `JigsawPlayScreen` (play) → solve → `JigsawCelebration`

- **Setup:** pick an image (Gallery or Portal sample, `category = Puzzle`) and difficulty
  (Easy 3×3 → Expert 6×6), then "Start Puzzle".
- **Procedural pieces** (`jigsaw_path_builder.dart`): grid subdivided into rows×cols; each
  interior edge is a cubic-Bézier knob generated once in board space and consumed by both
  neighbours (forward + reverse), guaranteeing zero gaps / no overlap. Each `PieceSpec` carries
  a closed Path, bounds, row/col, board position, and snap-target center.
- **Play:** drag pieces from the tray (`LongPressDraggable`) onto a zoom/pan board
  (`InteractiveViewer`); a piece snaps when its center is within a zoom-corrected threshold
  of home. HUD shows timer, move count, progress. Haptics on drag/snap/place/win. Edge-piece
  filter and 5 selectable board backgrounds are UX aids.
- **Win:** `place()` increments `placedCount`; reaching the total fires `JigsawCelebration`
  (stats card + confetti + "Play Again" / "New Image").

**Key files:** `jigsaw_puzzle_screen.dart`, `jigsaw_play_screen.dart`,
`controllers/jigsaw_controller.dart`, `jigsaw/jigsaw_path_builder.dart`,
`jigsaw/sample_images.dart`, `models/puzzle_piece.dart`, `widgets/jigsaw_tray.dart`,
`widgets/jigsaw_piece_view.dart`, `widgets/jigsaw_celebration.dart`.

---

## 5. Feature workflow: Authentication & Account (Tab 3)

**Flow:** app start → `AuthGate` → `LoginScreen` / `SignUpScreen` → signed-in → `AccountScreen`

- **Methods:** email/password and **Google OAuth** ("Continue with Gmail"); the Google token
  is exchanged for a Supabase session via `signInWithIdToken`.
- **Backend-less mode:** when `SUPABASE_*` env is missing, `AuthGate` skips login entirely and
  the app runs fully (auth calls throw `AuthUnavailable`). This keeps offline dev working.
- **portal_users mirror:** on every login `_syncPortalUser()` upserts `{id, email, full_name}`
  into `portal_users` (keyed on the auth UID). `_onAuthenticated()` checks `is_active`; a
  disabled account is signed out immediately. RLS limits each user to their own row.
- **Account screen:** avatar + email + "Signed in" + Sign out; shows a backend-disabled notice
  when no keys are present.

**Key files:** `services/auth_service.dart`, `screens/auth/login_screen.dart`,
`screens/auth/sign_up_screen.dart`, `screens/auth/account_screen.dart`,
`screens/auth/auth_validators.dart`, `widgets/auth/auth_text_field.dart`,
`widgets/auth/google_sign_in_button.dart`, `supabase/portal_users_rls.sql`.

---

## 6. Shared infrastructure

### Data layer — `svg_assets`
One Supabase table feeds all three content tabs, distinguished by `category`:

| `category` | Used by    | Purpose                  |
|------------|------------|--------------------------|
| `Drawing`  | AR Drawing | Overlay/trace presets    |
| `Painting` | Painting   | Coloring-page templates  |
| `Puzzle`   | Puzzle     | Sample reference photos  |

- **`SvgAsset`** model: `id, name, publicUrl, category, filePath, description, isActive`.
  `isActive = false` ⇒ locked/premium (rendered with a `LockedBadge`, not openable). `isSvg`
  decides `flutter_svg` vs raster `Image`.
- **`SvgAssetService`**: `fetch()`, `watch()` (Supabase Realtime stream), and `fetchGrouped()`.
  Active rows ordered first. Returns `[]` when Supabase is unconfigured.

### Theme — gradient + glass
`AppTheme` (Material 3, seeded from `AppColors.primary`) with light/dark variants.
`AppColors` (indigo-violet → magenta → pink brand seeds), `AppGradients`
(`hero`/`button`/`cool`/`pageLight`/`pageDark`/`bottomScrim`), `AppDimens` (spacing/radius/elevation).
Reusable widgets in `lib/widgets/common/`: `GlassCard`, `GradientAppBar`, `GradientBackground`,
`GradientButton`, `LockedBadge`, `NetworkAssetImage`, `NotificationBell`, `ResponsiveContainer`
(barrel: `common.dart`).

### Supabase schema (`supabase/*.sql`)
- **`svg_assets`** — portal-managed, read-only in app. RLS: authenticated SELECT all rows.
  Published to `supabase_realtime` for live `is_active`/row updates.
- **`saved_drawings`** — user content (`user_id`, `image_url`, `file_path`, `template_name`, …).
  RLS: insert/select/delete own rows only. Backed by a public, user-partitioned storage bucket
  (`<uid>/<timestamp>.png`).
- **`portal_users`** — login mirror. RLS: own row only.

### Configuration — `lib/config/app_config.dart` + `.env`
Secrets are injected at build time via `--dart-define-from-file=.env` (see `.env.example`).
Keys: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SVG_BUCKET`, `SUPABASE_POSTS_BUCKET`,
`SUPABASE_SAVED_BUCKET`, `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`, `FCM_SENDER_ID`,
`DEEP_LINK_SCHEME`. Guards: `isSupabaseConfigured`, `isGoogleSignInConfigured`, `isFcmConfigured`
let every backend call degrade gracefully when keys are absent.

```bash
flutter run --dart-define-from-file=.env
flutter build apk --dart-define-from-file=.env
```

---

## 7. Status summary

**Done (this branch):**
- 4-tab app shell with persistent tab state and auth gating.
- Painting/coloring with SVG region templates, full tool set, and cloud save.
- AR camera tracing with portal/gallery/SVG overlays.
- Procedural jigsaw puzzle with snapping, HUD, and celebration.
- Supabase auth (email + Google), `svg_assets` data layer with Realtime, `saved_drawings`
  + `portal_users` schemas, and the gradient/glass theme system.

**Pending / not yet wired:**
- Community posts (`user_posts` bucket exists in config, no feature yet).
- Push notifications (`FCM_SENDER_ID` scaffolded, not implemented).
- Deep linking (`arcreative://` scheme defined, no handler yet).
- Desktop/web save paths for drawings.
- Work on this branch is uncommitted — most features live in the working tree only.
```
