class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'DocuScan Pro';
  static const String appVersion = '1.0.0';
  static const String appTagline = 'The Free, All-in-One Document & PDF Platform';

  // Storage
  static const String documentsFolder = 'DocuScanPro';
  static const String scansFolder = 'Scans';
  static const String exportsFolder = 'Exports';
  static const String signaturesFolder = 'Signatures';
  static const String tempFolder = 'Temp';

  // Ad Configuration
  static const int interstitialFrequencyCapSeconds = 300; // 5 minutes
  static const int newUserGracePeriodHours = 24;
  static const int minSessionDurationForAd = 60; // seconds
  static const int maxBannerScreens = 3; // home, file browser, settings
  // A new "session" starts on cold launch, or when the app returns to the
  // foreground after being backgrounded for at least this long.
  static const int sessionTimeoutMinutes = 30;
  // Banners are shown only from this session number onward (PRD §7 Q4).
  static const int firstBannerSession = 2;

  // AdMob IDs (Test IDs - replace with real IDs before release)
  static const String bannerAdUnitIdAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const String bannerAdUnitIdIos = 'ca-app-pub-3940256099942544/2934735716';
  static const String interstitialAdUnitIdAndroid = 'ca-app-pub-3940256099942544/1033173712';
  static const String interstitialAdUnitIdIos = 'ca-app-pub-3940256099942544/4411468910';

  // Subscription
  static const String monthlySubscriptionId = 'docuscan_pro_monthly';
  static const String yearlySubscriptionId = 'docuscan_pro_yearly';
  static const double monthlyPrice = 2.99;
  static const double yearlyPrice = 24.99;

  // Cloud Conversion
  static const String cloudConversionBaseUrl = 'https://api.docuscanpro.com/convert';
  static const int cloudConversionTimeoutSeconds = 120;
  static const int maxCloudConversionsPerDay = 10;
  // Sent as the X-Api-Key header to the conversion microservice.
  // Empty = no header (backend must then allow anonymous calls).
  static const String cloudConversionApiKey = '';

  // RevenueCat public SDK keys (placeholders — RevenueCat is skipped at
  // startup while these still start with 'REPLACE_').
  static const String revenueCatApiKeyIos = 'REPLACE_WITH_REVENUECAT_IOS_PUBLIC_SDK_KEY';
  static const String revenueCatApiKeyAndroid = 'REPLACE_WITH_REVENUECAT_ANDROID_PUBLIC_SDK_KEY';
  static const String proEntitlementId = 'pro';

  // Cloud export — Dropbox (OAuth2 PKCE, no client secret in the app).
  // The redirect URI registered in the Dropbox app console must be
  // '<dropboxRedirectScheme>://oauth2redirect'. The scheme must also be
  // registered in AndroidManifest.xml (flutter_web_auth_2 CallbackActivity)
  // and ios/Runner/Info.plist (CFBundleURLSchemes).
  static const String dropboxAppKey = 'REPLACE_WITH_DROPBOX_APP_KEY';
  static const String dropboxRedirectScheme = 'db-REPLACE_WITH_DROPBOX_APP_KEY';
  static String get dropboxRedirectUri => '$dropboxRedirectScheme://oauth2redirect';

  // Cloud export — Google Drive (google_sign_in 7.x).
  // iOS: the iOS OAuth client ID (also set GIDClientID + the reversed client
  // ID URL scheme in ios/Runner/Info.plist).
  // Android: the *Web* OAuth client ID, used as serverClientId by Credential
  // Manager (the Android OAuth client must also exist with the app's SHA-1).
  static const String googleIosClientId = 'REPLACE_WITH_GOOGLE_IOS_CLIENT_ID.apps.googleusercontent.com';
  static const String googleServerClientId = 'REPLACE_WITH_GOOGLE_WEB_CLIENT_ID.apps.googleusercontent.com';

  // Folder (Drive) / path (Dropbox) that cloud uploads go into.
  static const String cloudExportFolderName = 'DocuScan Pro';

  /// True when [value] is still an unreplaced placeholder.
  static bool isPlaceholder(String value) =>
      value.isEmpty || value.contains('REPLACE_WITH') || value.startsWith('your_');

  // PDF Operations
  static const int maxMergeFiles = 20;
  static const int maxPdfPages = 500;
  static const double defaultJpegQuality = 0.85;

  // Compression Presets
  static const int compressionHigh = 72; // DPI
  static const int compressionMedium = 150;
  static const int compressionLow = 300;

  // Scan Settings
  static const double minScanResolution = 200.0;
  static const double defaultScanResolution = 300.0;
  static const double maxScanResolution = 600.0;

  // Supported File Types
  static const List<String> supportedImportTypes = [
    'pdf', 'jpg', 'jpeg', 'png', 'bmp', 'tiff', 'tif', 'gif', 'webp',
  ];

  static const List<String> supportedExportTypes = [
    'pdf', 'jpg', 'png', 'docx', 'xlsx', 'csv', 'txt',
  ];

  // Yousign (v1.1)
  static const int freeSignatureRequestsPerMonth = 10;
}
