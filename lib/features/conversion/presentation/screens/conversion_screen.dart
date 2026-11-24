import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/cloud_export_service.dart';
import 'package:docuscan_pro/core/services/conversion_service.dart';
import 'package:docuscan_pro/core/services/ad_service.dart';
import 'package:docuscan_pro/core/widgets/loading_overlay.dart';
import 'package:docuscan_pro/features/home/presentation/providers/home_provider.dart';

class ConversionScreen extends ConsumerStatefulWidget {
  const ConversionScreen({super.key});

  @override
  ConsumerState<ConversionScreen> createState() => _ConversionScreenState();
}

class _ConversionScreenState extends ConsumerState<ConversionScreen> {
  bool _isProcessing = false;
  String _statusMessage = '';

  /// User's manual engine choice for PDF→Word / PDF→Excel (PRD §7 Q1:
  /// on-device first, but users can always choose cloud themselves).
  bool _useCloud = false;

  // ---------------------------------------------------------------------------
  // Hybrid (on-device first, cloud on request / when quality is poor)
  // ---------------------------------------------------------------------------

  Future<void> _convertPdfToWord() =>
      _runHybrid(ConversionService.pdfToWord);

  Future<void> _convertPdfToExcel() =>
      _runHybrid(ConversionService.pdfToExcel);

  Future<void> _runHybrid(
    Future<ConversionResult> Function(String path, {bool useCloud}) convert,
  ) async {
    final path = await _pickFile(['pdf']);
    if (path == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = _useCloud ? 'Converting on our server...' : AppStrings.converting;
    });

    try {
      var result = await convert(path, useCloud: _useCloud);

      if (result.engine == ConversionEngine.onDevice && result.suggestCloud) {
        if (!mounted) return;
        // Either on-device failed, or it succeeded with a poor result.
        final wantCloud = await _showCloudDialog(result);
        if (wantCloud) {
          setState(() => _statusMessage = 'Converting on our server...');
          final cloud = await convert(path, useCloud: true);
          // Keep a usable on-device result if the cloud attempt fails.
          if (cloud.success || !result.success) {
            result = cloud;
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${cloud.error} — kept the on-device result'),
            ));
          }
        }
      }

      if (result.success) await _registerOutput(result.outputPath);

      await AdService.showInterstitialAd();

      if (!mounted) return;
      if (result.success) {
        _showSuccess(result);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? AppStrings.errorConversionFailed)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Conversion failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _registerOutput(String path) async {
    try {
      await ref.read(documentRepositoryProvider).saveOutputFile(path);
      ref.invalidate(recentDocumentsProvider);
    } catch (e) {
      debugPrint('Could not register converted file: $e');
    }
  }

  void _showSuccess(ConversionResult result) {
    final engine =
        result.engine == ConversionEngine.cloud ? ' (enhanced)' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${AppStrings.conversionComplete}$engine'),
        action: SnackBarAction(
          label: 'Share',
          onPressed: () =>
              CloudExportService.shareViaSystemSheet(result.outputPath),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // On-device only
  // ---------------------------------------------------------------------------

  Future<void> _convertPdfToImage() async {
    final path = await _pickFile(['pdf']);
    if (path == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = AppStrings.converting;
    });

    try {
      final result = await ConversionService.pdfToImage(path);

      await AdService.showInterstitialAd();

      if (!mounted) return;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Converted to ${result.outputPaths?.length ?? 1} image(s)',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? AppStrings.errorConversionFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _convertImageToPdf() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty) return;

    final paths = picked
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();
    if (paths.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = AppStrings.converting;
    });

    try {
      final convResult = await ConversionService.imageToPdf(paths);
      if (convResult.success) await _registerOutput(convResult.outputPath);

      await AdService.showInterstitialAd();

      if (!mounted) return;
      if (convResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.conversionComplete)),
        );
        context.push(
          '/pdf-viewer?path=${Uri.encodeComponent(convResult.outputPath)}',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(convResult.error ?? AppStrings.errorConversionFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<String?> _pickFile(List<String> extensions) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    return picked?.path;
  }

  /// Offers enhanced (cloud) conversion after an on-device attempt that
  /// failed or looks poor. Returns true if the user opts in.
  Future<bool> _showCloudDialog(ConversionResult onDevice) async {
    final reason = onDevice.success
        ? (onDevice.qualityNote ?? 'The on-device result may be incomplete.')
        : 'On-device conversion could not handle this file.';
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(AppStrings.enhancedConversion),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reason),
                const SizedBox(height: 12),
                const Text(AppStrings.enhancedConversionDesc),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(onDevice.success
                    ? 'Keep on-device result'
                    : AppStrings.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Use enhanced'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isProcessing,
      message: _statusMessage,
      child: Scaffold(
        appBar: AppBar(title: const Text(AppStrings.convertFiles)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ConversionOption(
              icon: Icons.description,
              title: AppStrings.pdfToWord,
              subtitle: 'Convert PDF to editable Word document',
              color: AppColors.primary,
              onTap: _convertPdfToWord,
            ),
            _ConversionOption(
              icon: Icons.table_chart,
              title: AppStrings.pdfToExcel,
              subtitle: 'Extract tables to spreadsheet format',
              color: AppColors.secondary,
              onTap: _convertPdfToExcel,
            ),
            _EngineSelector(
              useCloud: _useCloud,
              onChanged: (value) => setState(() => _useCloud = value),
            ),
            const SizedBox(height: 12),
            _ConversionOption(
              icon: Icons.image,
              title: AppStrings.pdfToImage,
              subtitle: 'Convert PDF pages to JPG/PNG images',
              color: AppColors.accent,
              onTap: _convertPdfToImage,
            ),
            _ConversionOption(
              icon: Icons.picture_as_pdf,
              title: AppStrings.imageToPdf,
              subtitle: 'Combine images into a PDF document',
              color: AppColors.pdfEdit,
              onTap: _convertImageToPdf,
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the user pick the engine for PDF→Word / PDF→Excel up front.
class _EngineSelector extends StatelessWidget {
  final bool useCloud;
  final ValueChanged<bool> onChanged;

  const _EngineSelector({required this.useCloud, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: RadioGroup<bool>(
          groupValue: useCloud,
          onChanged: (value) => onChanged(value ?? false),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Word & Excel conversion engine',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              RadioListTile<bool>(
                value: false,
                dense: true,
                title: Text(AppStrings.onDeviceConversionLabel),
              ),
              RadioListTile<bool>(
                value: true,
                dense: true,
                title: Text(AppStrings.enhancedConversionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversionOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ConversionOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  size: 16, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
