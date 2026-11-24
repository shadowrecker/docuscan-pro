#!/bin/bash
set -e

echo "========================================="
echo "  DocuScan Pro - Project Setup Script"
echo "========================================="
echo ""

# Check Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "ERROR: Flutter SDK not found in PATH."
    echo ""
    echo "Install Flutter:"
    echo "  1. Download from https://docs.flutter.dev/get-started/install"
    echo "  2. Extract and add to PATH:"
    echo "     export PATH=\"\$HOME/development/flutter/bin:\$PATH\""
    echo "  3. Run: flutter doctor"
    exit 1
fi

echo "[1/8] Flutter version:"
flutter --version
echo ""

# Download Poppins font files (Google Fonts, OFL license)
echo "[2/8] Downloading Poppins fonts..."
FONT_DIR="assets/fonts"
FONT_BASE="https://github.com/google/fonts/raw/main/ofl/poppins"
mkdir -p "$FONT_DIR"

for VARIANT in "Poppins-Regular" "Poppins-Medium" "Poppins-SemiBold" "Poppins-Bold"; do
    if [ ! -f "$FONT_DIR/$VARIANT.ttf" ]; then
        echo "  Downloading $VARIANT.ttf..."
        curl -sL "$FONT_BASE/$VARIANT.ttf" -o "$FONT_DIR/$VARIANT.ttf" 2>/dev/null || {
            echo "  WARNING: Could not download $VARIANT.ttf — you may need to add it manually"
        }
    else
        echo "  $VARIANT.ttf already exists"
    fi
done
echo ""

# Generate placeholder app icon if not present
echo "[3/8] Checking app icons..."
if [ ! -f "assets/icons/app_icon.png" ]; then
    echo "  WARNING: assets/icons/app_icon.png not found."
    echo "  Create a 1024x1024 PNG icon and place it at: assets/icons/app_icon.png"
    echo "  Then run: flutter pub run flutter_launcher_icons"
else
    echo "  App icon found"
fi
echo ""

# Run flutter pub get
echo "[4/8] Installing dependencies..."
flutter pub get
echo ""

# Check Firebase config
echo "[5/8] Checking Firebase configuration..."
if grep -q "YOUR_FIREBASE_API_KEY_HERE" "android/app/google-services.json" 2>/dev/null; then
    echo "  WARNING: Firebase is using placeholder config."
    echo "  To configure Firebase:"
    echo "    1. Go to https://console.firebase.google.com"
    echo "    2. Create a project named 'docuscan-pro'"
    echo "    3. Add Android app (com.docuscanpro.app) and download google-services.json"
    echo "    4. Add iOS app (com.docuscanpro.app) and download GoogleService-Info.plist"
    echo "    5. Replace the placeholder files in android/app/ and ios/Runner/"
    echo ""
    echo "  The app will still BUILD without real Firebase config, but analytics"
    echo "  and crashlytics won't function until configured."
fi
echo ""

# Check RevenueCat
echo "[6/8] Checking RevenueCat configuration..."
if grep -q "your_revenuecat_api_key" "lib/main.dart" 2>/dev/null; then
    echo "  WARNING: RevenueCat is using placeholder API key."
    echo "  To configure subscriptions:"
    echo "    1. Create account at https://www.revenuecat.com"
    echo "    2. Add your app and get the API key"
    echo "    3. Replace 'your_revenuecat_api_key' in lib/main.dart"
fi
echo ""

# Check AdMob
echo "[7/8] Checking AdMob configuration..."
echo "  Current config uses TEST Ad Unit IDs (safe for development)."
echo "  Before release, replace test IDs in lib/core/constants/app_constants.dart"
echo "  and AndroidManifest.xml / Info.plist with your real AdMob IDs."
echo ""

# Flutter doctor
echo "[8/8] Running Flutter doctor..."
flutter doctor
echo ""

echo "========================================="
echo "  Setup Complete!"
echo "========================================="
echo ""
echo "  To run on Android:  flutter run"
echo "  To run on iOS:      cd ios && pod install && cd .. && flutter run"
echo "  To build APK:       flutter build apk --release"
echo "  To build iOS:       flutter build ios --release"
echo ""
echo "  BEFORE RELEASE, configure:"
echo "  - Firebase (google-services.json / GoogleService-Info.plist)"
echo "  - RevenueCat API key (lib/main.dart)"
echo "  - AdMob real Ad Unit IDs (lib/core/constants/app_constants.dart)"
echo "  - App signing keys (Android keystore / iOS provisioning profile)"
echo "  - App icon (assets/icons/app_icon.png)"
echo "========================================="
