import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/pdf_service.dart';
import 'package:docuscan_pro/core/widgets/loading_overlay.dart';

class PageManagementScreen extends StatefulWidget {
  final String filePath;
  const PageManagementScreen({super.key, required this.filePath});

  @override
  State<PageManagementScreen> createState() => _PageManagementScreenState();
}

class _PageManagementScreenState extends State<PageManagementScreen> {
  List<int> _pageOrder = [];
  final Set<int> _selectedPages = {};
  bool _isSelectionMode = false;
  bool _isProcessing = false;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _loadPdfInfo();
  }

  Future<void> _loadPdfInfo() async {
    try {
      final info = await PdfService.getPdfInfo(widget.filePath);
      final count = info['pageCount'] as int? ?? 10;
      setState(() {
        _totalPages = count;
        _pageOrder = List.generate(count, (i) => i);
      });
    } catch (_) {
      setState(() {
        _totalPages = 10;
        _pageOrder = List.generate(10, (i) => i);
      });
    }
  }

  Future<void> _rotateSelected(int degrees) async {
    if (_selectedPages.isEmpty) return;
    setState(() => _isProcessing = true);
    try {
      final result = await PdfService.rotatePages(
        widget.filePath,
        _selectedPages.toList(),
        degrees,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pages rotated')),
        );
        // Rotation writes a new file; open it (same as delete).
        context.pushReplacement(
          '/pdf-viewer?path=${Uri.encodeComponent(result)}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rotation failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedPages.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Pages'),
        content: Text(
          'Delete ${_selectedPages.length} page(s)? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text(AppStrings.delete),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      final result = await PdfService.deletePages(
        widget.filePath,
        _selectedPages.toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pages deleted')),
        );
        context.pushReplacement(
          '/pdf-viewer?path=${Uri.encodeComponent(result)}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _insertPages() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('From Camera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('From Gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('From PDF File'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    List<String> pagePaths = [];

    if (source == 'camera') {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        // Convert image to a single-page PDF, then insert
        final pdfPath = await PdfService.createPdfFromImages([photo.path]);
        pagePaths = [pdfPath];
      }
    } else if (source == 'gallery') {
      final picker = ImagePicker();
      final images = await picker.pickMultiImage();
      if (images.isNotEmpty) {
        final pdfPath = await PdfService.createPdfFromImages(
          images.map((i) => i.path).toList(),
        );
        pagePaths = [pdfPath];
      }
    } else if (source == 'pdf') {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (picked?.path != null) {
        pagePaths = [picked!.path!];
      }
    }

    if (pagePaths.isEmpty || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      // Insert after the last selected page, or at the end
      final insertAt = _selectedPages.isEmpty
          ? _totalPages
          : _selectedPages.reduce((a, b) => a > b ? a : b) + 1;

      final result = await PdfService.insertPages(
        widget.filePath,
        insertAt,
        pagePaths,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pages inserted')),
        );
        context.pushReplacement(
          '/pdf-viewer?path=${Uri.encodeComponent(result)}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Insert failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveReorder() async {
    setState(() => _isProcessing = true);
    try {
      final result = await PdfService.reorderPages(
        widget.filePath,
        _pageOrder,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pages reordered')),
        );
        context.pushReplacement(
          '/pdf-viewer?path=${Uri.encodeComponent(result)}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reorder failed: $e')),
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
      message: AppStrings.processing,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.reorderPages),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Insert Pages',
              onPressed: _insertPages,
            ),
            if (_isSelectionMode && _selectedPages.isNotEmpty) ...[
              IconButton(
                icon: const Icon(Icons.rotate_right),
                tooltip: 'Rotate 90\u00b0',
                onPressed: () => _rotateSelected(90),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: AppStrings.delete,
                onPressed: _deleteSelected,
              ),
            ],
            TextButton(
              onPressed: _saveReorder,
              child: const Text(AppStrings.save),
            ),
          ],
        ),
        body: _totalPages == 0
            ? const Center(child: CircularProgressIndicator())
            : ReorderableGridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                padding: const EdgeInsets.all(16),
                childAspectRatio: 0.75,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    final item = _pageOrder.removeAt(oldIndex);
                    _pageOrder.insert(newIndex, item);
                  });
                },
                children: List.generate(_pageOrder.length, (i) {
                  final pageIndex = _pageOrder[i];
                  final isSelected = _selectedPages.contains(pageIndex);

                  return GestureDetector(
                    key: ValueKey(pageIndex),
                    onLongPress: () {
                      setState(() {
                        _isSelectionMode = true;
                        _selectedPages.add(pageIndex);
                      });
                    },
                    onTap: () {
                      if (_isSelectionMode) {
                        setState(() {
                          if (isSelected) {
                            _selectedPages.remove(pageIndex);
                            if (_selectedPages.isEmpty) _isSelectionMode = false;
                          } else {
                            _selectedPages.add(pageIndex);
                          }
                        });
                      }
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
                                  size: 32,
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.grey.shade400,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Page ${pageIndex + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
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
                                color: AppColors.primary,
                                size: 20,
                              ),
                            ),
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Icon(
                              Icons.drag_handle,
                              size: 16,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
      ),
    );
  }
}

// Simple reorderable grid (wraps ReorderableListView in grid layout)
class ReorderableGridView extends StatelessWidget {
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final EdgeInsets padding;
  final double childAspectRatio;
  final void Function(int, int) onReorder;
  final List<Widget> children;

  const ReorderableGridView.count({
    super.key,
    required this.crossAxisCount,
    this.crossAxisSpacing = 0,
    this.mainAxisSpacing = 0,
    this.padding = EdgeInsets.zero,
    this.childAspectRatio = 1.0,
    required this.onReorder,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView(
      padding: padding,
      onReorderItem: onReorder,
      buildDefaultDragHandles: false,
      children: [
        for (int i = 0; i < children.length; i += crossAxisCount)
          Padding(
            key: ValueKey('row_$i'),
            padding: EdgeInsets.only(bottom: mainAxisSpacing),
            child: Row(
              children: [
                for (int j = i; j < i + crossAxisCount && j < children.length; j++) ...[
                  if (j > i) SizedBox(width: crossAxisSpacing),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: childAspectRatio,
                      child: ReorderableDragStartListener(
                        index: j,
                        child: children[j],
                      ),
                    ),
                  ),
                ],
                // Fill remaining cells if last row is incomplete
                for (int k = 0;
                    k < crossAxisCount - (children.length - i).clamp(0, crossAxisCount);
                    k++) ...[
                  SizedBox(width: crossAxisSpacing),
                  const Expanded(child: SizedBox()),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
