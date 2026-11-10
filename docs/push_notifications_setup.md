# Push Notifications setup (FCM + Supabase)

The app code, native config, SQL, and the `send-push` Edge Function are already
in the repo. To make notifications actually **deliver**, complete the steps below
— they need your Firebase / Apple / Supabase accounts and can't be scripted.

Architecture: the app registers an FCM token → stores it in Supabase
`user_devices` → you insert a row into `notifications` → a Database Webhook calls
the `send-push` Edge Function → FCM delivers to every device the user is on.
Messages carry a `notification` block (shown by the OS in background/terminated)
and a `data` block (tap routing), so all three app states work.

App identifiers (Firebase apps must match):
- Android `applicationId`: `com.example.yammopatinerapp`
- iOS bundle id: `com.example.yammopatinerapp`

> ⚠️ Until the Firebase config files exist, the app **won't build** (the Android
> google-services Gradle plugin requires `google-services.json`). Do step 2 first.

---

## 1. Create the Firebase project
1. <https://console.firebase.google.com> → Add project.
2. Add an **Android** app, package name `com.example.yammopatinerapp`.
3. Add an **iOS** app, bundle id `com.example.yammopatinerapp`.

## 2. Add the config files (easiest: FlutterFire CLI)
```bash
dart pub global activate flutterfire_cli
flutterfire configure        # pick the project; select Android + iOS
```
This drops `android/app/google-services.json` and
`ios/Runner/GoogleService-Info.plist` in place (and writes
`lib/firebase_options.dart`, which is fine to keep — `Firebase.initializeApp()`
also works without it from the native files).

Manual alternative: download each file from the Firebase console and place them
at the two paths above. In Xcode, drag `GoogleService-Info.plist` into the
`Runner` target so it's bundled.

Put the project's **Sender ID** (Firebase → Project settings → Cloud Messaging)
into `.env`:
```
FCM_SENDER_ID=000000000000
```

## 3. iOS only — APNs (needs an Apple Developer account + a real device)
1. Apple Developer → Certificates, Identifiers & Profiles → Keys → **+** →
   enable **Apple Push Notifications service (APNs)** → download the `.p8`.
2. Firebase → Project settings → Cloud Messaging → **Apple app config** →
   upload the `.p8` with its Key ID and your Team ID.
3. In Xcode → `Runner` target → **Signing & Capabilities** → **+ Capability** →
   add **Push Notifications** (this wires `Runner.entitlements`, already created)
   and **Background Modes** → check **Remote notifications**.
4. Push does **not** work on the iOS Simulator — test on a physical device.

## 4. Supabase — schema + function + webhook
```bash
# Schema (or paste into Dashboard → SQL Editor)
supabase db execute -f supabase/user_devices.sql
supabase db execute -f supabase/notifications.sql

# Edge Function
supabase functions deploy send-push --no-verify-jwt
supabase secrets set \
  FIREBASE_PROJECT_ID=your-project-id \
  FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project-id.iam.gserviceaccount.com \
  FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```
- Get the three Firebase values from a **service account** JSON:
  Firebase → Project settings → **Service accounts** → *Generate new private key*.
  `FIREBASE_PRIVATE_KEY` is the `private_key` field verbatim (keep the `\n`s).
- `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.

Create the **webhook**: Dashboard → Database → Webhooks → *Create* →
table `public.notifications`, event **Insert**, type **Supabase Edge Functions**,
function **send-push**. (Or use the commented `pg_net` trigger in
`supabase/notifications.sql`.)

## 5. Build & run
```bash
flutter run --dart-define-from-file=.env
```
On first launch the app requests notification permission and saves the device
token to `user_devices` for the signed-in user.

## 6. Test all three states
Insert a row (Dashboard → SQL Editor), using a real signed-in user's id:
```sql
insert into public.notifications (user_id, title, body, data)
values ('<auth-uid>', 'Hello 👋', 'Your first push', '{"type":"test"}');
```
- **Foreground** — app open → banner appears (re-posted locally on Android).
- **Background** — home button, then insert → system notification; tap reopens.
- **Terminated** — swipe the app away, then insert → notification; tap launches
  it (handled via `getInitialMessage`).

You can also test delivery alone from Firebase → **Messaging** → *Send test
message* using a token printed in the debug console.

---

### Notes
- `com.example.*` is the default id. If you change it for the stores, update it
  in `android/app/build.gradle.kts`, the iOS bundle id, and the Firebase apps.
- Tapped-notification routing is a single hook today
  (`PushNotificationService._handleData`); point it at real destinations once
  notification `type`s are defined.
- A user signing out removes that device's token, so a shared phone stops
  receiving the previous account's notifications.
