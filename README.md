# DocLedger

In Pakistan, many private clinics operated by part-time doctors still rely on manual registers to record patient queues, visit details, and payments. This paper-based system is prone to errors, lacks data insights, and makes it difficult for doctors to track patient history, monthly revenue, or operational costs.

## Run locally on Linux

Prerequisites
- Flutter (stable) installed and on PATH
- Java 17 JDK (only needed for Android builds)

Clone and run
```bash
git clone https://github.com/DocLedger/DocLedger.git
cd DocLedger

# Optional: enable Linux desktop support (one-time)
flutter config --enable-linux-desktop

# Get packages
flutter pub get

# Run on Linux desktop
flutter run -d linux

# Build Android debug APK (optional)
flutter build apk --debug
# APK path: build/app/outputs/flutter-apk/app-debug.apk