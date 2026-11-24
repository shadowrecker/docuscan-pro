import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:docuscan_pro/core/services/ad_service.dart';

/// A widget that displays a Google AdMob banner ad.
///
/// Automatically hides itself (returns [SizedBox.shrink]) when the user is a
/// Pro subscriber or when ads are not ready to show. Properly loads and
/// disposes of the underlying [BannerAd].
class AdBannerWidget extends StatefulWidget {
  /// Optional padding around the banner.
  final EdgeInsetsGeometry padding;

  const AdBannerWidget({
    super.key,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    if (AdService.ready.value) {
      _loadAd();
    } else {
      // Ads finish initialising after the first screen is shown.
      AdService.ready.addListener(_onAdsReady);
    }
  }

  void _onAdsReady() {
    if (!AdService.ready.value) return;
    AdService.ready.removeListener(_onAdsReady);
    if (mounted) _loadAd();
  }

  void _loadAd() {
    if (!AdService.shouldShowBannerAd || _bannerAd != null) return;

    _bannerAd = BannerAd(
      adUnitId: AdService.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() => _isAdLoaded = true);
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdBannerWidget: failed to load – ${error.message}');
          ad.dispose();
          _bannerAd = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    AdService.ready.removeListener(_onAdsReady);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdService.shouldShowBannerAd || !_isAdLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: widget.padding,
      child: SizedBox(
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      ),
    );
  }
}
