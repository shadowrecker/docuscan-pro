import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/ad_service.dart';
import 'package:docuscan_pro/core/services/ocr_service.dart';
import 'package:docuscan_pro/core/services/pdf_service.dart';
import 'package:docuscan_pro/core/utils/file_utils.dart';
import 'package:docuscan_pro/core/widgets/loading_overlay.dart';
import 'package:docuscan_pro/features/home/presentation/providers/home_provider.dart';
import 'package:docuscan_pro/features/ocr/presentation/widgets/ocr_language_picker.dart';
import 'package:docuscan_pro/features/settings/presentation/providers/settings_provider.dart';

/// Text recognition for an image or a whole PDF (PRD O-01 / O-02).
///
/// PDFs are rasterised page by page via the native bridge and each page is
/// OCR'd; the combined text can be copied, and the per-page line boxes can be
/// turned into an invisible text layer to produce a searchable PDF.
class OcrScreen extends ConsumerStatefulWidget {
  final String filePath;
  const OcrScreen({super.key, required this.filePath});

  @override
  ConsumerState<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends ConsumerState<OcrScreen> {
  /// Rasterisation resolution for PDF pages; 300 dpi is the usual sweet spot
  /// for OCR accuracy.
  static const int _pdfOcrDpi = 300;

  late final bool _isPdf = FileUtils.isPdfFile(widget.filePath);
  OcrLanguage _language = OcrLanguage.english;

  /// Images that were OCR'd: the input image, or one PNG per PDF page.
  List<String> _pageImages = const [];

  /// Rasterised PDF pages we created (deleted on dispose).
  final List<String> _tempImages = [];

  /// Per-page OCR results, aligned with [_pageImages]. Null until run.
  List<OcrResult>? _results;
  String? _error;
  bool _isProcessing = false;
  String _progressMessage = AppStrings.ocrProcessing;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final path in _tempImages) {
      File(path).delete().ignore();
    }
    super.dispose();
  }

  Future<void> _init() async {
    // Restore the user's last OCR language.
    try {
      final codes = await ref.read(settingsRepositoryProvider).getOcrLanguages();
      final saved = codes.isEmpty ? null : OcrLanguage.fromCode(codes.first);
      if (saved != null) _language = saved;
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    await _runOcr();
  }

  // ---------------------------------------------------------------------------
  // OCR
  // ---------------------------------------------------------------------------

  String get _combinedText {
    final results = _results;
    if (results == null) return '';
    if (results.length == 1) return results.first.fullText.trim();
    final buffer = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      final text = results[i].fullText.trim();
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer
        ..writeln('— Page ${i + 1} —')
        ..write(text);
    }
    return buffer.toString();
  }

  bool get _hasText => _combinedText.isNotEmpty;

  void _setProgress(String message) {
    if (mounted) setState(() => _progressMessage = message);
  }

  Future<void> _runOcr() async {
    if (!await ensureOcrLanguageDownloaded(context, _language)) {
      if (mounted) {
        setState(() {
          _results = null;
          _error = '${_language.name} language pack is not downloaded. '
              'Choose another language or try again.';
        });
      }
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      // Rasterise PDF pages once; language changes reuse them.
      if (_pageImages.isEmpty) {
        if (_isPdf) {
          _setProgress(AppStrings.preparingPages);
          final images = await PdfService.pdfToImages(
            widget.filePath,
            dpi: _pdfOcrDpi,
          );
          _tempImages.addAll(images);
          _pageImages = images;
        } else {
          _pageImages = [widget.filePath];
        }
      }

      final results = <OcrResult>[];
      for (var i = 0; i < _pageImages.length; i++) {
        _setProgress(_pageImages.length > 1
            ? 'Recognizing text — page ${i + 1} of ${_pageImages.length}...'
            : AppStrings.ocrProcessing);
        results.add(await _recognizePage(_pageImages[i]));
      }

      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) {
        setState(() {
          _results = null;
          _error = 'OCR failed: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// OCRs one image, offering to download the language pack if the native
  /// side reports it missing (e.g. deleted since the last check).
  Future<OcrResult> _recognizePage(String imagePath) async {
    try {
      return await OcrService.recognize(imagePath, language: _language);
    } on OcrLanguageNotDownloadedException {
      if (!mounted) rethrow;
      final ok = await ensureOcrLanguageDownloaded(
        context,
        _language,
        skipCheck: true,
      );
      if (!ok) rethrow;
      return OcrService.recognize(imagePath, language: _language);
    }
  }

  Future<void> _chooseLanguage() async {
    final chosen = await showOcrLanguagePicker(context, selected: _language);
    if (chosen == null || chosen == _language || !mounted) return;
    setState(() => _language = chosen);
    ref.read(settingsProvider.notifier).setPrimaryOcrLanguage(chosen.code);
    await _runOcr();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _copyText() {
    if (!_hasText) return;
    Clipboard.setData(ClipboardData(text: _combinedText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.textCopied)),
    );
  }

  Future<void> _extractTable() async {
    if (_pageImages.isEmpty) return;
    var pageIndex = 0;
    if (_pageImages.length > 1) {
      final chosen = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Extract table from page'),
          children: [
            for (var i = 0; i < _pageImages.length; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, i),
                child: Text('Page ${i + 1}'),
              ),
          ],
        ),
      );
      if (chosen == null) return;
      pageIndex = chosen;
    }
    if (!mounted) return;
    context.push(
      '/table-extraction?path=${Uri.encodeComponent(_pageImages[pageIndex])}',
    );
  }

  /// Builds the invisible text layer from the per-page OCR line boxes and
  /// saves the result as a new document.
  Future<void> _makeSearchablePdf() async {
    final results = _results;
    if (!_isPdf || results == null) return;

    setState(() {
      _isProcessing = true;
      _progressMessage = 'Creating searchable PDF...';
    });
    try {
      final pages = <OcrTextLayerPage>[];
      for (var i = 0; i < results.length; i++) {
        final size = await PdfService.getImageSize(_pageImages[i]);
        pages.add(OcrTextLayerPage(
          pageIndex: i,
          imageWidth: size.width,
          imageHeight: size.height,
          lines: [
            for (final line in results[i].allLines)
              if (line.text.trim().isNotEmpty)
                OcrTextLayerLine(
                  text: line.text,
                  left: line.boundingBox.left,
                  top: line.boundingBox.top,
                  width: line.boundingBox.width,
                  height: line.boundingBox.height,
                ),
          ],
        ));
      }

      final outputPath = await PdfService.addOcrTextLayer(
        widget.filePath,
        pages: pages,
      );

      await ref.read(documentRepositoryProvider).saveOutputFile(
            outputPath,
            pageCount: pages.length,
            ocrText: _combinedText,
          );
      ref.invalidate(recentDocumentsProvider);

      await AdService.showInterstitialAd();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.searchablePdfCreated)),
      );
      context.push('/pdf-viewer?path=${Uri.encodeComponent(outputPath)}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isProcessing,
      message: _progressMessage,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.extractText),
          actions: [
            if (_hasText)
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: AppStrings.copyText,
                onPressed: _copyText,
              ),
          ],
        ),
        body: Column(
          children: [
            // Language selector
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.translate, size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  const Text('${AppStrings.ocrLanguage}:'),
                  const SizedBox(width: 8),
                  ActionChip(
                    label: Text(_language.name),
                    avatar: Icon(
                      _language.usesMlKit ? Icons.bolt : Icons.download_done,
                      size: 18,
                    ),
                    onPressed: _isProcessing ? null : _chooseLanguage,
                  ),
                  const Spacer(),
                  if (_isPdf)
                    const Chip(
                      label: Text('PDF'),
                      avatar: Icon(Icons.picture_as_pdf, size: 18),
                    ),
                ],
              ),
            ),

            // Results
            Expanded(child: _buildBody(context)),

            // Bottom actions
            if (_hasText)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _copyText,
                              icon: const Icon(Icons.copy),
                              label: const Text(AppStrings.copyText),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _extractTable,
                              icon: const Icon(Icons.table_chart),
                              label: const Text(AppStrings.extractTable),
                            ),
                          ),
                        ],
                      ),
                      if (_isPdf) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isProcessing ? null : _makeSearchablePdf,
                            icon: const Icon(Icons.manage_search),
                            label: const Text(AppStrings.makeSearchablePdf),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);

    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        text: _error!,
        actionLabel: AppStrings.retry,
        onAction: _runOcr,
      );
    }

    final results = _results;
    if (results == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasText) {
      return _Message(
        icon: Icons.text_snippet_outlined,
        text: AppStrings.noTextFound,
        actionLabel: AppStrings.retry,
        onAction: _runOcr,
      );
    }

    final blockCount = results.fold<int>(0, (sum, r) => sum + r.blocks.length);
    final pageLabel = results.length > 1 ? '${results.length} pages · ' : '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.secondary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$pageLabel$blockCount text blocks found '
                    '(${results.first.engine})',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Extracted text
          SelectableText(
            _combinedText,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  const _Message({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
