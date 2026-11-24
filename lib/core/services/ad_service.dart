import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:docuscan_pro/core/constants/app_constants.dart';
import 'package:docuscan_pro/repositories/settings_repository.dart';

/// Pure ad-eligibility rules from PRD §7 Q4 / §9, kept free of plugins and
/// statics so they can be unit-tested with an explicit `now`.
class AdPolicy {
  AdPolicy._();

  /// Banners: never for Pro users, and only from session 2 onward.
  static bool canShowBanner({
    required bool isProUser,
    required int sessionCount,
  }) {
    if (isProUser) return false;
    return sessionCount >= AppConstants.firstBannerSession;
  }

  /// Interstitials: never for Pro users, never during active editing,
  /// never in the first 24 h after install, never in sessions shorter than
  /// 60 s, and at most once per 5-minute rolling window.
  static bool canShowInterstitial({
    required DateTime now,
    required bool isProUser,
    required bool isInEditingMode,
    required DateTime? installDate,
    required DateTime? sessionStart,
    required DateTime? lastInterstitial,
  }) {
    if (isProUser) return false;
    if (isInEditingMode) return false;

    // 24-hour grace period for new users. Unknown install date = treat as new.
    if (installDate == null) return false;
    if (now.difference(installDate) <
        const Duration(hours: AppConstants.newUserGracePeriodHours)) {
      return false;
    }

    // Short-session respect.
    if (sessionStart == null) return false;
    if (now.difference(sessionStart) <
        const Duration(seconds: AppConstants.minSessionDurationForAd)) {
      return false;
    }

    // Frequency cap.
    if (lastInterstitial != null &&
        now.difference(lastInterstitial) <
            const Duration(
                seconds: AppConstants.interstitialFrequencyCapSeconds)) {
      return false;
    }

    return true;
  }
}

/// Tracks app sessions.
///
/// A session starts on cold launch, and a new one starts when the app comes
/// back to the foreground after having been in the background for at least
/// [timeout] (30 min by default — the common analytics definition, so a quick
/// app switch to copy a password doesn't count as a new session).
class AdSessionTracker {
  AdSessionTracker({
    DateTime Function()? clock,
    this.timeout = const Duration(minutes: AppConstants.sessionTimeoutMinutes),
    int initialSessionCount = 0,
  })  : _clock = clock ?? DateTime.now,
        _sessionCount = initialSessionCount;

  final DateTime Function() _clock;
  final Duration timeout;

  int _sessionCount;
  DateTime? _sessionStart;
  DateTime? _backgroundedAt;

  int get sessionCount => _sessionCount;
  DateTime? get sessionStart => _sessionStart;

  /// Starts a new session (cold launch). Returns the new session number.
  int startSession() {
    _sessionCount++;
    _sessionStart = _clock();
    _backgroundedAt = null;
    return _sessionCount;
  }

  void onBackgrounded() {
    _backgroundedAt ??= _clock();
  }

  /// Returns true if returning to the foreground started a new session.
  bool onForegrounded() {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null) return false;
    if (_clock().difference(backgroundedAt) >= timeout) {
      startSession();
      return true;
    }
    return false;
  }
}

class AdService {
  AdService._();

  static bool _isInitialized = false;
  static bool _isProUser = false;
  static bool _isInEditingMode = false;
  static DateTime? _installDate;
  static DateTime? _lastInterstitialTime;
  static InterstitialAd? _interstitialAd;
  static SettingsRepository? _settings;
  static AppLifecycleListener? _lifecycleListener;
  static AdSessionTracker _sessions = AdSessionTracker();

  static bool get isProUser => _isProUser;
  static int get sessionCount => _sessions.sessionCount;

  /// Call when the user enters an active editing screen (PDF editor,
  /// annotations, fill & sign, signature pad). While in editing mode,
  /// interstitial ads are suppressed — per PRD rule "never during active work".
  static void enterEditingMode() {
    _isInEditingMode = true;
  }

  /// Call when the user leaves an editing screen.
  static void exitEditingMode() {
    _isInEditingMode = false;
  }

  static String get bannerAdUnitId => Platform.isAndroid
      ? AppConstants.bannerAdUnitIdAndroid
      : AppConstants.bannerAdUnitIdIos;

  static String get interstitialAdUnitId => Platform.isAndroid
      ? AppConstants.interstitialAdUnitIdAndroid
      : AppConstants.interstitialAdUnitIdIos;

  /// Loads the persisted install date / session counter, starts a new
  /// session, and initialises the Mobile Ads SDK. Never throws — ad failures
  /// must not block app startup.
  /// Becomes true once the Mobile Ads SDK has initialised. The SDK can take
  /// tens of seconds (or time out offline), so the app doesn't wait for it at
  /// startup; widgets that show ads listen to this instead.
  static final ValueNotifier<bool> ready = ValueNotifier(false);

  static Future<void> initialize({SettingsRepository? settings}) async {
    if (_isInitialized) return;

    _settings = settings ?? SettingsRepository();
    try {
      _installDate = await _settings!.getFirstLaunchDate();
      final previousCount = await _settings!.getSessionCount();
      _sessions = AdSessionTracker(initialSessionCount: previousCount);
    } catch (e) {
      debugPrint('AdService: failed to load install/session data: $e');
      // Treat as a brand-new install: no interstitials, no banners.
      _installDate = DateTime.now();
    }
    _sessions.startSession();
    await _persistSessionCount();

    _lifecycleListener ??= AppLifecycleListener(
      onHide: _sessions.onBackgrounded,
      onShow: () {
        if (_sessions.onForegrounded()) _persistSessionCount();
      },
    );

    try {
      await MobileAds.instance.initialize();
      _isInitialized = true;
      ready.value = true;
      _loadInterstitialAd();
    } catch (e) {
      debugPrint('AdService: MobileAds init failed: $e');
    }
  }

  static Future<void> _persistSessionCount() async {
    try {
      await _settings?.setSessionCount(_sessions.sessionCount);
    } catch (e) {
      debugPrint('AdService: failed to persist session count: $e');
    }
  }

  static void setProUser(bool isPro) {
    _isProUser = isPro;
  }

  static bool get shouldShowBannerAd {
    if (!_isInitialized) return false;
    return AdPolicy.canShowBanner(
      isProUser: _isProUser,
      sessionCount: _sessions.sessionCount,
    );
  }

  static bool get shouldShowInterstitialAd {
    if (!_isInitialized) return false;
    return AdPolicy.canShowInterstitial(
      now: DateTime.now(),
      isProUser: _isProUser,
      isInEditingMode: _isInEditingMode,
      installDate: _installDate,
      sessionStart: _sessions.sessionStart,
      lastInterstitial: _lastInterstitialTime,
    );
  }

  static void _loadInterstitialAd() {
    if (_isProUser) return;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _loadInterstitialAd(); // Preload next
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              _loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial ad failed to load: ${error.message}');
          // Retry after delay
          Future.delayed(const Duration(seconds: 30), _loadInterstitialAd);
        },
      ),
    );
  }

  static Future<void> showInterstitialAd() async {
    if (!shouldShowInterstitialAd) return;
    if (_interstitialAd == null) return;

    _lastInterstitialTime = DateTime.now();
    await _interstitialAd!.show();
  }

  static BannerAd createBannerAd() {
    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner ad failed to load: ${error.message}');
          ad.dispose();
        },
      ),
    );
  }

  static void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }
}
