import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_constants.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/widgets/ad_banner_widget.dart';
import 'package:docuscan_pro/core/services/ocr_service.dart';
import 'package:docuscan_pro/core/services/storage_service.dart';
import 'package:docuscan_pro/features/ocr/presentation/widgets/ocr_language_picker.dart';
import 'package:docuscan_pro/features/settings/presentation/providers/settings_provider.dart';
import 'package:docuscan_pro/models/scan_settings_model.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settings)),
      body: ListView(
        children: [
          // Upgrade to Pro Card
          if (!settings.isProUser)
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showProDialog(context),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 36),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                AppStrings.upgradeToPro,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Remove ads for just \$${AppConstants.monthlyPrice}/month',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios,
                            color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Appearance Section
          const _SectionHeader(title: AppStrings.appearance),
          ListTile(
            leading: const Icon(Icons.dark_mode),
            title: const Text(AppStrings.darkMode),
            subtitle: Text(_themeModeLabel(settings.themeMode)),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 18)),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_android, size: 18)),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 18)),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (set) => notifier.setThemeMode(set.first),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),

          // Scanning Section
          const _SectionHeader(title: 'Scanning'),
          ListTile(
            leading: const Icon(Icons.filter),
            title: const Text(AppStrings.defaultScanFilter),
            trailing: DropdownButton<ScanFilter>(
              value: settings.defaultScanFilter,
              underline: const SizedBox(),
              onChanged: (filter) {
                if (filter != null) notifier.setDefaultScanFilter(filter);
              },
              items: ScanFilter.values.map((f) {
                return DropdownMenuItem(
                  value: f,
                  child: Text(f.displayName),
                );
              }).toList(),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.crop_free),
            title: const Text(AppStrings.autoDetect),
            subtitle: const Text('Automatically detect document edges'),
            value: settings.autoEdgeDetection,
            onChanged: notifier.setAutoEdgeDetection,
          ),

          // OCR Section
          const _SectionHeader(title: 'OCR'),
          ListTile(
            leading: const Icon(Icons.translate),
            title: const Text(AppStrings.ocrLanguages),
            subtitle: Text('${settings.ocrLanguages.length} language(s) selected'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showLanguagePicker(context, ref),
          ),

          // Storage Section
          const _SectionHeader(title: AppStrings.storage),
          FutureBuilder<int>(
            future: StorageService.getDirectorySize(StorageService.appDocumentsDir),
            builder: (context, snapshot) {
              final size = snapshot.data ?? 0;
              return ListTile(
                leading: const Icon(Icons.storage),
                title: const Text(AppStrings.storageUsed),
                subtitle: Text(StorageService.formatFileSize(size)),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text(AppStrings.clearCache),
            subtitle: const Text('Remove temporary files'),
            onTap: () async {
              await StorageService.clearTemp();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache cleared')),
                );
              }
            },
          ),

          // About Section
          const _SectionHeader(title: AppStrings.about),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text(AppStrings.version),
            subtitle: Text(AppConstants.appVersion),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text(AppStrings.privacyPolicy),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text(AppStrings.termsOfService),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: const Text(AppStrings.rateApp),
            onTap: () {},
          ),
          if (settings.isProUser)
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text(AppStrings.restorePurchases),
              onTap: () {},
            ),

          const SizedBox(height: 8),
          const AdBannerWidget(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System default';
    }
  }

  void _showProDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Icon(Icons.star, color: Colors.amber, size: 48),
            const SizedBox(height: 16),
            const Text(
              'DocuScan Pro',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Remove all ads and enjoy a clean experience',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const _ProBenefit(icon: Icons.block, text: 'No banner or interstitial ads'),
            const _ProBenefit(icon: Icons.speed, text: 'Faster processing'),
            const _ProBenefit(icon: Icons.email, text: 'Priority email support'),
            const _ProBenefit(icon: Icons.new_releases, text: 'Early access to new features'),
            const _ProBenefit(icon: Icons.draw, text: 'Unlimited signature requests'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Subscribe - \$${AppConstants.monthlyPrice}/month',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Annual - \$${AppConstants.yearlyPrice}/year (save 30%)',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(AppStrings.restorePurchases),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    AppStrings.ocrLanguages,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(AppStrings.done),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _OcrLanguageList(scrollController: scrollController),
            ),
          ],
        ),
      ),
    );
  }
}

/// Multi-select list of OCR languages. ML Kit languages work immediately;
/// Tesseract languages must have their pack downloaded first, which happens
/// when they're selected (or via the download button).
class _OcrLanguageList extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  const _OcrLanguageList({required this.scrollController});

  @override
  ConsumerState<_OcrLanguageList> createState() => _OcrLanguageListState();
}

class _OcrLanguageListState extends ConsumerState<_OcrLanguageList> {
  Set<String> _downloaded = {};

  @override
  void initState() {
    super.initState();
    _refreshDownloaded();
  }

  Future<void> _refreshDownloaded() async {
    final downloaded = await loadDownloadedOcrLanguages();
    if (mounted) setState(() => _downloaded = downloaded);
  }

  Future<void> _download(OcrLanguage lang) async {
    final ok = await ensureOcrLanguageDownloaded(context, lang, skipCheck: true);
    if (ok) await _refreshDownloaded();
  }

  Future<void> _toggle(OcrLanguage lang, bool isSelected) async {
    final notifier = ref.read(settingsProvider.notifier);
    if (!isSelected && !isOcrLanguageReady(lang, _downloaded)) {
      final ok =
          await ensureOcrLanguageDownloaded(context, lang, skipCheck: true);
      if (!ok) return;
      await _refreshDownloaded();
    }
    notifier.toggleOcrLanguage(lang.code);
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(settingsProvider).ocrLanguages;

    Widget tile(OcrLanguage lang) {
      final isSelected = selected.contains(lang.code);
      final ready = isOcrLanguageReady(lang, _downloaded);
      return CheckboxListTile(
        title: Text(lang.name),
        subtitle: Text(lang.usesMlKit
            ? 'On-device'
            : (ready ? 'Downloaded' : 'Download required')),
        value: isSelected,
        onChanged: (_) => _toggle(lang, isSelected),
        secondary: lang.usesMlKit || ready
            ? null
            : IconButton(
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Download',
                onPressed: () => _download(lang),
              ),
      );
    }

    return ListView(
      controller: widget.scrollController,
      children: [
        const _SectionHeader(title: 'On-device'),
        ...OcrLanguage.onDevice.map(tile),
        const _SectionHeader(title: 'Downloadable (Tesseract)'),
        ...OcrLanguage.tesseract.map(tile),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ProBenefit extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ProBenefit({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }
}
