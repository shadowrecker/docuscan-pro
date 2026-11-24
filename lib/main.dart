import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:docuscan_pro/app/app.dart';
import 'package:docuscan_pro/core/constants/app_constants.dart';
import 'package:docuscan_pro/core/services/storage_service.dart';
import 'package:docuscan_pro/core/services/ad_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Each third-party SDK is initialised defensively: with placeholder config
  // files / keys (or no network) the app must still launch.
  await _initFirebase();
  await _initRevenueCat();

  // Initialize core services
  await StorageService.initialize();
  // Not awaited: the Mobile Ads SDK can take tens of seconds (or time out
  // offline), and nothing on the first screen depends on it.
  unawaited(AdService.initialize());

  runApp(
    const ProviderScope(
      child: DocuScanProApp(),
    ),
  );
}

/// Initialises Firebase and, only if that succeeds, installs the Crashlytics
/// error handlers. Placeholder google-services.json / GoogleService-Info.plist
/// make `initializeApp` throw, in which case we log and carry on.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    debugPrint('Firebase init failed — analytics/crash reporting disabled: $e');
    debugPrintStack(stackTrace: st, maxFrames: 5);
    return;
  }

  // Configure Crashlytics — forward all Flutter and platform errors.
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}

/// Configures RevenueCat for subscription management. Skipped while the API
/// key in [AppConstants] is still a placeholder; failures are logged and the
/// user is treated as a free user.
Future<void> _initRevenueCat() async {
  final apiKey = Platform.isIOS
      ? AppConstants.revenueCatApiKeyIos
      : AppConstants.revenueCatApiKeyAndroid;
  if (AppConstants.isPlaceholder(apiKey)) {
    debugPrint('RevenueCat API key is a placeholder — purchases disabled.');
    return;
  }

  try {
    // Anonymous app user ID until the user signs in.
    await Purchases.configure(PurchasesConfiguration(apiKey));

    // Listen to subscription changes and update ad service accordingly
    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      AdService.setProUser(customerInfo.entitlements.active
          .containsKey(AppConstants.proEntitlementId));
    });
  } catch (e) {
    debugPrint('RevenueCat configure failed — purchases disabled: $e');
    return;
  }

  // Check current subscription status at launch
  try {
    final customerInfo = await Purchases.getCustomerInfo();
    AdService.setProUser(customerInfo.entitlements.active
        .containsKey(AppConstants.proEntitlementId));
  } catch (_) {
    // Offline or first launch — default to free user
  }
}
