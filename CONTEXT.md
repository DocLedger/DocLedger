## DocLedger – Project Context

### What we are building
- **Purpose**: Replace paper registers for private clinics with a simple app to manage queues, visits, and revenue.
- **MVP Scope**: Single device, offline-first; login, basic patient/visit/payment tracking, daily reports, export/import. Subscriptions and cloud sync added later.

### Platform targets
- **Android** (phones/tablets): primary now
- **Windows desktop**: build and package (MSIX/EXE) next
- iOS: out of scope for now (maybe later)

### Tech stack
- **Framework**: Flutter (Dart)
- **Flutter**: 3.32.8 • **Dart**: 3.8.1
- **State/DB**: To be added later (likely Riverpod + Drift/SQLite). For now, no business logic beyond demo login.

### Decisions to date
- Single codebase in Flutter for Android + Windows
- Offline-first; local storage (SQLite) later
- Subscriptions via Stripe + lightweight license API (post-MVP)

### Current implementation
- Basic navigation with a demo login screen that routes to a welcome page
  - Files:
    - `lib/main.dart`
    - `lib/features/auth/presentation/login_page.dart`
    - `lib/features/welcome/presentation/welcome_page.dart`
- Demo credentials (hard-coded):
  - Username: `admin@clinic`
  - Password: `Passw0rd!`

### Build/run
- Android (debug APK):
  - Output: `build/app/outputs/flutter-apk/app-debug.apk`
  - Install: `adb install -r build/app/outputs/flutter-apk/app-debug.apk`
  - Run: `flutter run -d <deviceId>`
- Linux (local sanity runs only): enabled for development
- Windows: build on a Windows machine with Visual Studio 2022 + Windows 10/11 SDK
  - `flutter build windows --release`
  - Packaging (later): MSIX via `msix` tool

### Next steps (short list)
1. Windows build path: verify on a Windows host; add MSIX packaging
2. Data layer setup: Drift/SQLite schema (patients, queue, visits, payments)
3. Real auth (later): move demo login to proper auth/license flow
4. Implement core screens (patients, queue, visits, payments) – offline-first
5. Reports and export/import

### Non-goals for MVP
- Multi-device realtime sync
- App store billing (Stripe direct only at first)
- Printing/receipt support

### Notes
- Keep UI simple, fast to navigate with keyboard/mouse and touch.
- Prioritize reliability and data safety (later: encrypted DB and backups).