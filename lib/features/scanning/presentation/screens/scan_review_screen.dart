import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/ad_service.dart';
import 'package:docuscan_pro/core/services/pdf_service.dart';
import 'package:docuscan_pro/core/widgets/loading_overlay.dart';
import 'package:docuscan_pro/features/scanning/presentation/providers/scanner_provider.dart';
import 'package:docuscan_pro/features/scanning/presentation/screens/scanner_screen.dart';
import 'package:docuscan_pro/models/document_model.dart';
import 'package:docuscan_pro/models/scan_settings_model.dart';
import 'package:docuscan_pro/repositories/document_repository.dart';

class ScanReviewScreen extends ConsumerStatefulWidget {
  final List<String> imagePaths;
  final ScanMode scanMode;

  const ScanReviewScreen({
    super.key,
    required this.imagePaths,
    required this.scanMode,
  });

  @override
  ConsumerState<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends ConsumerState<ScanReviewScreen> {
  late final PageController _pageController;
  late final TextEditingController _titleController;
  int _currentPage = 0;
  ScanFilter _selectedFilter = ScanFilter.enhanced;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final prefix = widget.scanMode == ScanMode.whiteboard ? 'Whiteboard' : 'Scan';
    _titleController = TextEditingController(text: '${prefix}_$timestamp');

    // Initialize scanner state with the passed images
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(scannerProvider.notifier);
      notifier.clear();
      for (final path in widget.imagePaths) {
        notifier.addImage(path);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _savePdf() async {
    setState(() => _isProcessing = true);

    try {
      // Apply filter to all images
      if (_selectedFilter != ScanFilter.original) {
        ref.read(scannerProvider.notifier).setFilter(_selectedFilter);
        await ref.read(scannerProvider.notifier).applyFilterToAll();
      }

      final images = ref.read(scannerProvider).capturedImages;

      // Create PDF from images
      final pdfPath = await PdfService.createPdfFromImages(
        images,
        title: _titleController.text.trim(),
      );

      // Save document to repository
      final doc = await DocumentModel.createFromFile(File(pdfPath));
      final repo = DocumentRepository();
      await repo.save(doc.copyWith(
        title: _titleController.text.trim(),
        pageCount: images.length,
      ));

      if (!mounted) return;

      // Show interstitial ad
      await AdService.showInterstitialAd();

      if (!mounted) return;

      // Clear scanner state
      ref.read(scannerProvider.notifier).clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document saved successfully')),
      );

      // Navigate to PDF viewer
      context.go('/pdf-viewer?path=${Uri.encodeComponent(pdfPath)}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scannerState = ref.watch(scannerProvider);
    final images = scannerState.capturedImages.isNotEmpty
        ? scannerState.capturedImages
        : widget.imagePaths;

    return LoadingOverlay(
      isLoading: _isProcessing,
      message: AppStrings.processing,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Review Scan'),
          actions: [
            TextButton(
              onPressed: _isProcessing ? null : _savePdf,
              child: const Text('Save PDF'),
            ),
          ],
        ),
        body: Column(
          children: [
            // Title field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Document Title',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
            ),

            // Page indicator
            if (images.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(images.length, (i) {
                    return Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _currentPage
                            ? AppColors.primary
                            : Colors.grey.shade300,
                      ),
                    );
                  }),
                ),
              ),

            // Image preview
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: images.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(images[index]),
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
            ),

            // Filter options
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: ScanFilter.values.map((filter) {
                    final isSelected = filter == _selectedFilter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(filter.displayName),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() => _selectedFilter = filter);
                        },
                        selectedColor: AppColors.primary.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: isSelected ? AppColors.primary : null,
                          fontWeight: isSelected ? FontWeight.w600 : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  _ActionButton(
                    icon: Icons.rotate_right,
                    label: AppStrings.rotatePage,
                    onTap: () async {
                      ref.read(scannerProvider.notifier).setCurrentPageIndex(_currentPage);
                      await ref.read(scannerProvider.notifier).rotateCurrent();
                    },
                  ),
                  const SizedBox(width: 12),
                  _ActionButton(
                    icon: Icons.add_a_photo,
                    label: AppStrings.addPage,
                    onTap: () => context.push('/scanner?mode=${widget.scanMode.name}'),
                  ),
                  const SizedBox(width: 12),
                  _ActionButton(
                    icon: Icons.replay,
                    label: AppStrings.retake,
                    onTap: () {
                      ref.read(scannerProvider.notifier).removeImage(_currentPage);
                      if (ref.read(scannerProvider).capturedImages.isEmpty) {
                        context.pop();
                      }
                    },
                  ),
                ],
              ),
            ),

            // Save button
            Padding(
              padding: EdgeInsets.fromLTRB(
                16, 0, 16, MediaQuery.of(context).padding.bottom + 16,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _isProcessing ? null : _savePdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text('Save as PDF (${images.length} pages)'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
