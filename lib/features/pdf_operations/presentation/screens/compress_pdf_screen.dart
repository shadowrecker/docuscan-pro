import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/pdf_service.dart';
import 'package:docuscan_pro/core/services/ad_service.dart';
import 'package:docuscan_pro/core/services/storage_service.dart';
import 'package:docuscan_pro/core/widgets/loading_overlay.dart';

class CompressPdfScreen extends StatefulWidget {
  final String filePath;
  const CompressPdfScreen({super.key, required this.filePath});

  @override
  State<CompressPdfScreen> createState() => _CompressPdfScreenState();
}

class _CompressPdfScreenState extends State<CompressPdfScreen> {
  CompressionLevel _selectedLevel = CompressionLevel.medium;
  bool _isProcessing = false;
  int _originalSize = 0;
  int? _compressedSize;
  String? _compressedPath;

  @override
  void initState() {
    super.initState();
    _loadFileInfo();
  }

  Future<void> _loadFileInfo() async {
    final file = File(widget.filePath);
    if (await file.exists()) {
      final stat = await file.stat();
      setState(() => _originalSize = stat.size);
    }
  }

  Future<void> _compress() async {
    setState(() => _isProcessing = true);

    try {
      final result = await PdfService.compressPdf(
        widget.filePath,
        level: _selectedLevel,
      );

      final compressedFile = File(result);
      final stat = await compressedFile.stat();

      await AdService.showInterstitialAd();

      if (!mounted) return;
      setState(() {
        _compressedSize = stat.size;
        _compressedPath = result;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Compression failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = widget.filePath.split('/').last;

    return LoadingOverlay(
      isLoading: _isProcessing,
      message: 'Compressing PDF...',
      child: Scaffold(
        appBar: AppBar(title: const Text(AppStrings.compressPdf)),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // File info card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.picture_as_pdf, color: Colors.red),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fileName,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Original: ${StorageService.formatFileSize(_originalSize)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'Compression Level',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),

              // Compression options
              ...CompressionLevel.values.map((level) {
                final isSelected = level == _selectedLevel;
                final estimatedSize = (_originalSize * _estimatedRatioForLevel(level)).round();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedLevel = level),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                        color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : null,
                      ),
                      child: Row(
                        children: [
                          // Whole card is tappable (GestureDetector above).
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: isSelected ? AppColors.primary : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  level.label,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  _levelDescription(level),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '~${StorageService.formatFileSize(estimatedSize)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isSelected ? AppColors.primary : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              // Results card
              if (_compressedSize != null) ...[
                const SizedBox(height: 24),
                Card(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.secondary, size: 36),
                        const SizedBox(height: 8),
                        const Text('Compression Complete!',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(StorageService.formatFileSize(_originalSize)),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.arrow_forward, size: 16),
                            ),
                            Text(
                              StorageService.formatFileSize(_compressedSize!),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(((1 - _compressedSize! / _originalSize) * 100)).toStringAsFixed(1)}% reduction',
                          style: const TextStyle(color: AppColors.secondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const Spacer(),

              // Action buttons
              SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: _compressedPath != null
                      ? FilledButton.icon(
                          onPressed: () => context.pushReplacement(
                            '/pdf-viewer?path=${Uri.encodeComponent(_compressedPath!)}',
                          ),
                          icon: const Icon(Icons.visibility),
                          label: const Text('View Compressed PDF'),
                        )
                      : FilledButton.icon(
                          onPressed: _compress,
                          icon: const Icon(Icons.compress),
                          label: const Text('Compress'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _estimatedRatioForLevel(CompressionLevel level) {
    switch (level) {
      case CompressionLevel.high:
        return 0.3;
      case CompressionLevel.medium:
        return 0.55;
      case CompressionLevel.low:
        return 0.8;
    }
  }

  String _levelDescription(CompressionLevel level) {
    switch (level) {
      case CompressionLevel.high:
        return 'Smallest file size, lower quality';
      case CompressionLevel.medium:
        return 'Balanced size and quality';
      case CompressionLevel.low:
        return 'Best quality, larger file size';
    }
  }
}
