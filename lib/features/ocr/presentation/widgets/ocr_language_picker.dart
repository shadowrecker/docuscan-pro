import 'package:flutter/material.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/ocr_service.dart';

/// Returns the set of downloaded Tesseract language packs (by tesseract
/// code). Empty if the native side can't report them.
Future<Set<String>> loadDownloadedOcrLanguages() async {
  final codes = await OcrService.getAvailableLanguages();
  return codes.toSet();
}

bool isOcrLanguageReady(OcrLanguage language, Set<String> downloaded) =>
    language.usesMlKit ||
    downloaded.contains(language.tesseractCode) ||
    downloaded.contains(language.code);

/// Makes sure [language] can be used for recognition. ML Kit languages are
/// always ready; for Tesseract languages that aren't downloaded yet, asks the
/// user to download the pack and downloads it with a progress dialog.
///
/// Set [skipCheck] when the caller already knows the pack is missing (e.g.
/// after a `LANGUAGE_NOT_DOWNLOADED` error). Returns true when ready.
Future<bool> ensureOcrLanguageDownloaded(
  BuildContext context,
  OcrLanguage language, {
  bool skipCheck = false,
}) async {
  if (language.usesMlKit) return true;
  if (!skipCheck) {
    final downloaded = await loadDownloadedOcrLanguages();
    if (isOcrLanguageReady(language, downloaded)) return true;
  }
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Download ${language.name}?'),
          content: Text(
            '${language.name} text recognition needs a one-time language pack '
            'download (typically 1–15 MB). After that it works offline.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(AppStrings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Download'),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirmed || !context.mounted) return false;

  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text('Downloading ${language.name}...')),
          ],
        ),
      ),
    ),
  );
  final ok = await OcrService.downloadLanguagePack(language.tesseractCode);
  navigator.pop();

  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not download ${language.name}. '
            'Check your connection and try again.'),
      ),
    );
  }
  return ok;
}

/// Bottom sheet for choosing a single OCR language. On-device (ML Kit)
/// languages are listed first, then Tesseract languages with their download
/// status. Returns the chosen language, or null if dismissed.
Future<OcrLanguage?> showOcrLanguagePicker(
  BuildContext context, {
  required OcrLanguage selected,
}) {
  return showModalBottomSheet<OcrLanguage>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) => FutureBuilder<Set<String>>(
        future: loadDownloadedOcrLanguages(),
        builder: (context, snapshot) {
          final downloaded = snapshot.data ?? const <String>{};
          Widget tile(OcrLanguage lang) {
            final ready = isOcrLanguageReady(lang, downloaded);
            return ListTile(
              title: Text(lang.name),
              subtitle: Text(
                lang.usesMlKit
                    ? 'On-device'
                    : (ready ? 'Downloaded' : 'Download required'),
              ),
              leading: Icon(
                lang == selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: lang == selected ? AppColors.primary : null,
              ),
              trailing: lang.usesMlKit || ready
                  ? null
                  : const Icon(Icons.download_outlined, size: 20),
              onTap: () => Navigator.pop(context, lang),
            );
          }

          return ListView(
            controller: scrollController,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'OCR Language',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              const _SheetHeader('On-device (fast, no download)'),
              ...OcrLanguage.onDevice.map(tile),
              const _SheetHeader('More languages (Tesseract, offline after download)'),
              ...OcrLanguage.tesseract.map(tile),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    ),
  );
}

class _SheetHeader extends StatelessWidget {
  final String title;
  const _SheetHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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
