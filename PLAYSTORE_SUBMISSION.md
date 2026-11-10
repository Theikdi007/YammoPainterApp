# Play Store Submission Checklist — Panda Paint

## Template Assets (in `docs/playstore/`)

| File | Description |
|---|---|
| `app_icon_512x512.svg` | App icon template — convert to PNG before upload |
| `feature_graphic_1024x500.svg` | Feature graphic template |
| `screenshot_phone_1_painting.svg` | Painting tab screenshot |
| `screenshot_phone_2_coloring.svg` | Coloring book screenshot |
| `screenshot_phone_3_puzzle.svg` | Jigsaw puzzle screenshot |
| `screenshot_phone_4_profile.svg` | Profile tab screenshot |

> **Note:** SVG files are templates. Convert to PNG (512×512 for icon, 1024×500 for feature graphic, 1080×1920 for screenshots) before uploading to Play Console.

---

## Required Images & Assets

### 1. App Icon (High-Resolution)
- **Size:** 512 x 512 px
- **Format:** PNG (32-bit RGBA)
- **Location:** Upload to Play Console — not the same as the launcher icon in `res/mipmap-*`
- **Note:** This is the icon shown on the Play Store listing, NOT the on-device launcher icon

### 2. Feature Graphic (Banner)
- **Size:** 1024 x 500 px
- **Format:** PNG or JPEG
- **Note:** Shown at the top of the store listing on larger screens

### 3. Phone Screenshots
- **Min:** 2 screenshots
- **Max:** 8 screenshots
- **Size:** 320 px – 3840 px (longest side)
- **Aspect ratio:** 16:9 or 9:16
- **Format:** PNG or JPEG
- **Recommended resolutions:**
  - 1080 x 1920 (portrait)
  - 1920 x 1080 (landscape)

### 4. Tablet Screenshots (optional but recommended)
- **Size:** 320 px – 3840 px (longest side)
- **Aspect ratio:** 16:10 or 10:16
- **Recommended resolutions:**
  - 1200 x 1920 (portrait)
  - 1920 x 1200 (landscape)

### 5. Promo Video (optional)
- **Format:** YouTube link
- **Note:** Can significantly increase conversion

---

## Store Listing Details

### Title
- **Max:** 30 characters
- **Current:** `Panda Paint`

### Short Description
- **Max:** 80 characters
- **Current:** `Freehand drawing, coloring book templates, AR tracing & jigsaw puzzles — unleash your creativity!` (91 chars — trim to 80)
- **Trimmed:** `Freehand drawing, coloring book, AR tracing & jigsaw puzzles — create!` (72 chars)

### Full Description
- **Max:** 4000 characters

```
🐼 Panda Paint — Draw, Color, Create!

Unleash your creativity with Panda Paint, the all-in-one drawing and coloring app for all ages. Whether you're sketching freely, filling in coloring book templates, tracing with AR, or solving jigsaw puzzles — Panda Paint has something for everyone.

🎨 FREEHAND DRAWING
• Draw with your finger or stylus on a clean canvas
• Choose from a wide range of colors with the HSV color picker
• Adjust stroke width for fine details or bold lines
• Unlimited undo/redo — never lose your progress
• Save your masterpieces to your gallery

📖 COLORING BOOK TEMPLATES
• Beautiful pre-made templates: hearts, stars, flowers, butterflies, circles and more
• Per-stroke clipping keeps your colors inside the lines
• Import your own SVG files as custom coloring templates
• Perfect for relaxing creative sessions

📷 AR DRAWING
• Trace images using your phone's camera as a guide
• Overlay any reference photo on your camera view
• Adjust opacity and position for perfect tracing
• Great for learning to draw real-world subjects

🧩 JIGSAW PUZZLE
• Turn your drawings and photos into jigsaw puzzles
• Multiple difficulty levels
• Drag-and-drop pieces to solve
• Track your progress with a completion bar

💾 SAVE & SHARE
• Save drawings in high quality (3x resolution export)
• Share your creations with friends and family
• Your gallery syncs across devices with cloud backup

🔔 SMART NOTIFICATIONS
• Get notified about new templates and features
• Customizable notification preferences

🐼 WHY PANDA PAINT?
• Beautiful, intuitive Material Design interface
• Works offline — draw anywhere, anytime
• No ads interrupting your creative flow
• Suitable for kids and adults alike
• Free to use with no hidden fees

Download Panda Paint today and start creating! Whether you're an aspiring artist, a parent looking for a safe creative app for your kids, or just someone who loves to doodle — Panda Paint is the perfect canvas for your imagination.
```

**Character count:** ~1,850 / 4,000

---

## App Content Requirements

### Privacy Policy
- **Required:** Yes — must be hosted at a public URL
- **Note:** App uses camera, photo library, and push notifications — privacy policy must disclose all data collection

### Content Rating
- **Required:** Complete IARC questionnaire
- **Likely rating:** Everyone (no violent, sexual, or mature content)

### Data Safety Section
- **Required:** Declare all data the app collects and shares
- **Data types to declare:**
  - Camera (device sensors)
  - Photos/Media/Files (saved drawings)
  - Notifications (FCM push)
  - Network communication (Supabase, image loading)

### App Access
- **Required:** Provide demo account or instructions if app requires login
- **Current:** Supabase auth (email/password + Google sign-in)

---

## Technical Requirements

| Requirement | Status |
|---|---|
| `applicationId` unique (not `com.example.*`) | ❌ Currently `com.example.pandapainterapp` |
| `minSdk` ≥ 21 | ✅ Uses Flutter default |
| `targetSdk` current | ✅ Uses Flutter default |
| 64-bit native libraries | ✅ (Flutter handles this) |
| App Bundle (AAB) format | Build with `flutter build appbundle` |
| Signing config for release | ❌ TODO: Add release keystore |
| Remove test ad IDs | ✅ Production IDs set |
| Remove `debugShowCheckedModeBanner: false` | N/A — already false |
| No placeholder/test content | ✅ |
| Content rating questionnaire completed | ❌ TODO |

---

## Build Commands

```bash
# Build release AAB for Play Store
flutter build appbundle --release

# Build release APK (for testing)
flutter build apk --release

# Output locations
# AAB: build/app/outputs/bundle/release/app-release.aab
# APK: build/app/outputs/flutter-apk/app-release.apk
```

---

## Steps Before Submission

1. **Change `applicationId`** from `com.example.pandapainterapp` to a unique ID (e.g., `com.yourcompany.pandapaint`)
2. **Set up release signing** in `android/app/build.gradle.kts`
3. **Create 512x512 app icon** for Play Console upload
4. **Create 1024x500 feature graphic**
5. **Take 2-8 phone screenshots** of the app in action
6. **Write privacy policy** and host it at a public URL
7. **Complete content rating questionnaire** in Play Console
8. **Fill out data safety section** in Play Console
9. **Build AAB** with `flutter build appbundle --release`
10. **Upload to Play Console** and submit for review
