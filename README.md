# DocuScan Pro

A free, ad-supported document scanner and PDF toolkit for Android and iOS, built with Flutter. It covers scanning (documents, whiteboards, QR codes), on-device OCR, PDF editing and annotation, page management, forms and signatures, conversion, and password protection.

PDF work runs on-device: Apache PDFBox on Android, Apple PDFKit on iOS. OCR uses Google ML Kit, plus Tesseract for scripts ML Kit doesn't cover. An optional cloud service (`cloud_backend/`) handles complex Word, Excel and PowerPoint conversions.

## Repository layout

| Path | Contents |
|---|---|
| `lib/` | Flutter app (Riverpod, go_router) |
| `android/app/src/main/kotlin/` | Native Android code: `PdfBoxHandler.kt` (PDF operations), `TesseractHandler.kt` (OCR), `CloudConversionHandler.kt` |
| `ios/Runner/` | Native iOS code: `PdfHandler.swift` (PDFKit), `TesseractOcrHandler.swift` (SwiftyTesseract), `CloudConversionHandler.swift` |
| `cloud_backend/` | Conversion microservice (FastAPI + LibreOffice, Cloud Run). See its [README](cloud_backend/README.md). |
| `integration_test/` | On-device checks for every native PDF/OCR operation |
| `test/` | Unit tests |

## Requirements

- Flutter 3.47 (stable) or later
- Java 17 for Android builds
- Xcode 26 and CocoaPods for iOS builds

## Setup

1. **Install packages**
   ```bash
   flutter pub get
   cd ios && pod install && cd ..
   ```

2. **Add the Firebase config files.** These are deliberately not in the repository. Download them from the Firebase console for an Android app `com.docuscanpro.app` and an iOS app with the same bundle ID:
   - `android/app/google-services.json` (the Android build fails without it)
   - `ios/Runner/GoogleService-Info.plist`. Then open `ios/Runner.xcworkspace` in Xcode and drag the file into the **Runner** group, ticking **Add to target: Runner**. The Xcode project doesn't reference it yet, so iOS won't load it otherwise.

3. **Replace the placeholder keys.** Search the code for `REPLACE_WITH`.
   - `lib/core/constants/app_constants.dart`:
     - RevenueCat public SDK keys (iOS and Android)
     - Dropbox app key and redirect scheme
     - Google iOS client ID and web client ID
     - Cloud conversion URL and API key
     - AdMob ad unit IDs. These are currently **Google's test IDs**; replace them before release.
   - `ios/Runner/Info.plist`: Google client ID and Dropbox URL schemes
   - `android/app/src/main/AndroidManifest.xml`: Dropbox redirect scheme
   - AdMob app IDs: `GADApplicationIdentifier` in `Info.plist`, and `com.google.android.gms.ads.APPLICATION_ID` in `AndroidManifest.xml`

   The app runs with the placeholders. Firebase, purchases, Drive/Dropbox upload and real ads stay disabled until they're filled in.

4. **iOS signing:** in Xcode, open **Runner target → Signing & Capabilities** and choose your team.

## Running

```bash
flutter run            # on a connected device or emulator
```

The iOS app **can't run in the iOS Simulator** on Apple Silicon Macs. ML Kit ships no arm64-simulator build, and current simulators are arm64-only. Use a real iPhone.

## Tests

```bash
flutter analyze
flutter test                                   # unit tests
```

On-device checks (13 tests covering text editing, compression, encryption, forms, annotations, OCR, page operations and signatures):

```bash
# Android
flutter test integration_test/native_ops_test.dart -d <emulator-or-device-id>

# iPhone: use `flutter run`. `flutter test` uninstalls the app when it finishes,
# which makes iOS forget the developer trust and show "Untrusted Developer" each time.
flutter run -t integration_test/native_ops_test.dart -d <iphone-udid>
```

On a Mac where Flutter was installed via Homebrew, macOS may block Flutter's iPhone connection helper (`iproxy`). If so, clear the download flag on Flutter's iOS tools:

```bash
cd "$(dirname "$(readlink -f "$(which flutter)")")/cache/artifacts" && \
  xattr -dr com.apple.quarantine libusbmuxd libimobiledevice libimobiledeviceglue libplist openssl ios-deploy
```

The terminal or IDE running Flutter also needs **Local Network** permission (System Settings → Privacy & Security → Local Network).

## Building for release

```bash
flutter build appbundle                        # Play Store
flutter build ipa                              # App Store / TestFlight
```

Android release builds are currently signed with the debug key (`android/app/build.gradle`). Set up a release keystore before publishing. `key.properties` and keystores are git-ignored.

## Known limitations

- **iOS text editing covers the original text instead of removing it.** PDFKit can't rewrite page content, so the edit draws over the old text, which stays hidden in the file and is still found by search and copy. Android replaces the text in place where the font allows it.
- **iOS dependencies use CocoaPods only** (`enable-swift-package-manager: false` in `pubspec.yaml`). `google_mlkit_*` has no Swift Package Manager support, and mixing the two linked Google's shared libraries twice. Firebase stopped publishing to CocoaPods after October 2026, so future Firebase upgrades depend on ML Kit gaining Swift Package Manager support.
- `permission_handler` is pinned to 12.x: 13.x needs Android compileSdk 37, which requires Android Gradle Plugin 9.
- Flutter warns that the UIScene app lifecycle will soon be required on iOS. That migration hasn't been done yet.

## Licence

Copyright © 2026 Navroop Srivastava. All rights reserved.

This repository is public so the code can be viewed as a portfolio project. No licence is granted: you may not copy, modify, distribute or use the code without written permission.

The bundled Poppins fonts (`assets/fonts/`) are third-party and licensed separately under the [SIL Open Font License 1.1](assets/fonts/OFL.txt).
