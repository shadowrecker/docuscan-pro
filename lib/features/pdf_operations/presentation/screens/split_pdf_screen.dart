import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/pdf_service.dart';
import 'package:docuscan_pro/core/services/ad_service.dart';
import 'package:docuscan_pro/core/widgets/loading_overlay.dart';

class SplitPdfScreen extends StatefulWidget {
  final String filePath;
  const SplitPdfScreen({super.key, required this.filePath});

  @override
  State<SplitPdfScreen> createState() => _SplitPdfScreenState();
}

class _SplitPdfScreenState extends State<SplitPdfScreen> {
  final Set<int> _selectedPages = {};
  final TextEditingController _rangeController = TextEditingController();
  int _totalPages = 0;
  bool _isProcessing = false;
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    _loadPdfInfo();
  }

  @override
  void dispose() {
    _rangeController.dispose();
    super.dispose();
  }

  Future<void> _loadPdfInfo() async {
    try {
      final info = await PdfService.getPdfInfo(widget.filePath);
      setState(() => _totalPages = info['pageCount'] as int? ?? 10);
    } catch (_) {
      setState(() => _totalPages = 10);
    }
  }

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedPages.addAll(List.generate(_totalPages, (i) => i));
      } else {
        _selectedPages.clear();
      }
    });
  }

  void _applyRange() {
    final text = _rangeController.text.trim();
    if (text.isEmpty) return;

    final pages = <int>{};
    for (final part in text.split(',')) {
      final trimmed = part.trim();
      if (trimmed.contains('-')) {
        final range = trimmed.split('-');
        if (range.length == 2) {
          final start = int.tryParse(range[0].trim());
          final end = int.tryParse(range[1].trim());
          if (start != null && end != null) {
            for (int i = start; i <= end && i <= _totalPages; i++) {
              if (i >= 1) pages.add(i - 1);
            }
          }
        }
      } else {
        final page = int.tryParse(trimmed);
        if (page != null && page >= 1 && page <= _totalPages) {
          pages.add(page - 1);
        }
      }
    }

    setState(() {
      _selectedPages.clear();
      _selectedPages.addAll(pages);
    });
  }

  Future<void> _splitPdf() async {
    if (_selectedPages.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final pages = _selectedPages.toList()..sort();
      final results = await PdfService.splitPdf(widget.filePath, pages);

      await AdService.showInterstitialAd();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Split into ${results.length} file(s)')),
      );
      context.pushReplacement(
        '/pdf-viewer?path=${Uri.encodeComponent(results.first)}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Split failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isProcessing,
      message: 'Splitting PDF...',
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.splitPdf),
          actions: [
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(_selectAll ? 'Deselect All' : 'Select All'),
            ),
          ],
        ),
        body: Column(
          children: [
            // Range input
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _rangeController,
                      decoration: const InputDecoration(
                        hintText: 'e.g., 1-5, 8, 10-12',
                        labelText: 'Page Range',
                        prefixIcon: Icon(Icons.filter_list),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _applyRange,
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),

            // Page grid
            Expanded(
              child: _totalPages == 0
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: _totalPages,
                      itemBuilder: (context, index) {
                        final isSelected = _selectedPages.contains(index);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedPages.remove(index);
                              } else {
                                _selectedPages.add(index);
                              }
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.1)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.description,
                                        size: 28,
                                        color: isSelected
                                            ? AppColors.primary
                                            : Colors.grey,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? AppColors.primary
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Icon(
                                      Icons.check_circle,
                                      size: 20,
                                      color: AppColors.primary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Split button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _selectedPages.isNotEmpty ? _splitPdf : null,
                    icon: const Icon(Icons.call_split),
                    label: Text(
                      _selectedPages.isEmpty
                          ? 'Select pages to extract'
                          : 'Extract ${_selectedPages.length} Page(s)',
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
