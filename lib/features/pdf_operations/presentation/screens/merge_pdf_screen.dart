import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:docuscan_pro/core/services/pdf_service.dart';
import 'package:docuscan_pro/core/services/ad_service.dart';
import 'package:docuscan_pro/core/services/storage_service.dart';
import 'package:docuscan_pro/core/utils/file_utils.dart';
import 'package:docuscan_pro/core/widgets/loading_overlay.dart';
import 'package:docuscan_pro/features/home/presentation/providers/home_provider.dart';

/// Screen that allows users to select multiple PDFs and/or images, reorder
/// them, and merge them into a single PDF document (PRD E-04).
class MergePdfScreen extends ConsumerStatefulWidget {
  const MergePdfScreen({super.key});

  @override
  ConsumerState<MergePdfScreen> createState() => _MergePdfScreenState();
}

class _MergePdfScreenState extends ConsumerState<MergePdfScreen> {
  static const _imageExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  final List<_MergeFileEntry> _files = [];
  bool _isProcessing = false;

  bool get _canMerge => _files.length >= 2 && !_isProcessing;

  // ---------------------------------------------------------------------------
  // File picking
  // ---------------------------------------------------------------------------

  Future<void> _pickFiles() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', ..._imageExtensions],
    );

    if (picked.isEmpty) return;

    final entries = <_MergeFileEntry>[];
    for (final pf in picked) {
      final path = pf.path;
      if (path == null) continue;
      final stat = await File(path).stat();
      entries.add(_MergeFileEntry(
        path: path,
        name: FileUtils.getFileName(path),
        sizeBytes: stat.size,
        isImage: _imageExtensions
            .contains(FileUtils.getFileExtension(path).replaceFirst('.', '')),
      ));
    }

    setState(() => _files.addAll(entries));
  }

  // ---------------------------------------------------------------------------
  // Merge
  // ---------------------------------------------------------------------------

  Future<void> _merge() async {
    if (!_canMerge) return;

    setState(() => _isProcessing = true);

    // Single-page PDFs generated from images; removed once merged.
    final tempPdfs = <String>[];
    try {
      // Convert images to single-page PDFs, preserving the user's order.
      final paths = <String>[];
      for (var i = 0; i < _files.length; i++) {
        final entry = _files[i];
        if (entry.isImage) {
          final pdf = await PdfService.createPdfFromImages(
            [entry.path],
            title: 'merge_part_${DateTime.now().millisecondsSinceEpoch}_$i',
            outputDir: StorageService.tempDir,
          );
          tempPdfs.add(pdf);
          paths.add(pdf);
        } else {
          paths.add(entry.path);
        }
      }

      final outputPath = await PdfService.mergePdfs(paths);

      // Register the result so it appears in Recent / file browser.
      await ref.read(documentRepositoryProvider).saveOutputFile(
            outputPath,
            pageCount: await PdfService.getPageCount(outputPath),
          );
      ref.invalidate(recentDocumentsProvider);

      if (!mounted) return;

      // Show interstitial ad after merge completes.
      await AdService.showInterstitialAd();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Files merged successfully')),
      );

      context.pushNamed(
        'pdf-viewer',
        queryParameters: {'path': outputPath},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to merge files: $e')),
      );
    } finally {
      for (final path in tempPdfs) {
        File(path).delete().ignore();
      }
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Reorder
  // ---------------------------------------------------------------------------

  /// [newIndex] is already adjusted for the removed item (onReorderItem).
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _files.removeAt(oldIndex);
      _files.insert(newIndex, item);
    });
  }

  void _removeFile(int index) {
    setState(() => _files.removeAt(index));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LoadingOverlay(
      isLoading: _isProcessing,
      message: 'Merging files...',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Merge PDFs'),
        ),
        body: Column(
          children: [
            // Add files button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _pickFiles,
                  icon: const Icon(Icons.add),
                  label: const Text('Add PDFs or Images'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: colorScheme.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),

            // File list
            Expanded(
              child: _files.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.merge_type_rounded,
                            size: 64,
                            color: colorScheme.onSurface.withValues(alpha: 0.25),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Add at least 2 PDFs or images to merge',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _files.length,
                      onReorderItem: _onReorder,
                      buildDefaultDragHandles: false,
                      proxyDecorator: (child, index, animation) {
                        return Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.transparent,
                          child: child,
                        );
                      },
                      itemBuilder: (context, index) {
                        final file = _files[index];
                        return _FileTile(
                          // Same file may be added twice; key by identity.
                          key: ObjectKey(file),
                          index: index,
                          entry: file,
                          onDelete: () => _removeFile(index),
                        );
                      },
                    ),
            ),

            // Merge button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _canMerge ? _merge : null,
                    icon: const Icon(Icons.merge_type_rounded),
                    label: Text(
                      _files.length < 2
                          ? 'Select at least 2 files'
                          : 'Merge ${_files.length} Files',
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

class _MergeFileEntry {
  final String path;
  final String name;
  final int sizeBytes;
  final bool isImage;

  const _MergeFileEntry({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.isImage,
  });
}

class _FileTile extends StatelessWidget {
  final int index;
  final _MergeFileEntry entry;
  final VoidCallback onDelete;

  const _FileTile({
    super.key,
    required this.index,
    required this.entry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: entry.isImage ? Colors.blue.shade50 : Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: entry.isImage
              ? Image.file(
                  File(entry.path),
                  fit: BoxFit.cover,
                  cacheWidth: 88,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.image, color: Colors.blue),
                )
              : const Icon(Icons.picture_as_pdf, color: Colors.red),
        ),
        title: Text(
          entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${entry.isImage ? 'Image' : 'PDF'} · '
          '${FileUtils.formatFileSize(entry.sizeBytes)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: theme.colorScheme.error,
              onPressed: onDelete,
              tooltip: 'Remove',
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle),
            ),
          ],
        ),
      ),
    );
  }
}
