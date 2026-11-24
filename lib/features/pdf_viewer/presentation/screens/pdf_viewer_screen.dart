import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/cloud_export_service.dart';
import 'package:docuscan_pro/features/pdf_viewer/presentation/providers/pdf_viewer_provider.dart';

/// Full-featured PDF viewer built on top of [SfPdfViewer].
///
/// Supports pinch-to-zoom, page navigation, in-document text search, sharing,
/// printing, and an overflow menu linking to every PDF operation screen.
class PdfViewerScreen extends ConsumerStatefulWidget {
  final String filePath;

  const PdfViewerScreen({super.key, required this.filePath});

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  late final PdfViewerController _pdfController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  PdfTextSearchResult? _searchResult;

  String get _documentTitle {
    final name = widget.filePath.split('/').last;
    // Strip the extension for a cleaner title.
    final dotIndex = name.lastIndexOf('.');
    return dotIndex > 0 ? name.substring(0, dotIndex) : name;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
  }

  @override
  void dispose() {
    _pdfController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchResult?.clear();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Search helpers
  // ---------------------------------------------------------------------------

  void _startSearch(String query) {
    if (query.trim().isEmpty) return;
    _searchResult?.clear();
    _searchResult = _pdfController.searchText(query);
    _searchResult!.addListener(_onSearchResultChanged);
  }

  void _onSearchResultChanged() {
    if (_searchResult == null) return;
    // The listener fires on every incremental result. We simply trigger a
    // rebuild so the match count updates in real time.
    if (mounted) setState(() {});
  }

  void _clearSearch() {
    _searchResult?.clear();
    _searchResult = null;
    _searchController.clear();
    ref.read(pdfViewerProvider.notifier).toggleSearch();
  }

  void _nextMatch() {
    _searchResult?.nextInstance();
    setState(() {});
  }

  void _previousMatch() {
    _searchResult?.previousInstance();
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Sharing / printing
  // ---------------------------------------------------------------------------

  Future<void> _sharePdf() async {
    final file = File(widget.filePath);
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.errorFileNotFound)),
        );
      }
      return;
    }

    // Show export options: system share sheet or direct cloud upload
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Export To',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share Sheet'),
              subtitle: const Text('iCloud, OneDrive, AirDrop, and more'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: const Text('Google Drive'),
              subtitle: CloudExportService.isGoogleDriveConfigured
                  ? null
                  : const Text('Not configured — uses share sheet'),
              onTap: () => Navigator.pop(ctx, 'gdrive'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_circle),
              title: const Text('Dropbox'),
              subtitle: CloudExportService.isDropboxConfigured
                  ? null
                  : const Text('Not configured — uses share sheet'),
              onTap: () => Navigator.pop(ctx, 'dropbox'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    switch (choice) {
      case 'share':
        await CloudExportService.shareViaSystemSheet(
          widget.filePath,
          subject: _documentTitle,
        );
      case 'gdrive':
        await _uploadToCloud(
          CloudExportService.uploadToGoogleDrive(widget.filePath),
          'Google Drive',
        );
      case 'dropbox':
        await _uploadToCloud(
          CloudExportService.uploadToDropbox(widget.filePath),
          'Dropbox',
        );
    }
  }

  /// Runs a cloud upload and reports the outcome. If the provider isn't
  /// configured in this build, says so and falls back to the share sheet.
  Future<void> _uploadToCloud(
    Future<CloudUploadResult> upload,
    String providerName,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Uploading to $providerName...')),
    );
    final result = await upload;
    if (!mounted) return;
    messenger.hideCurrentSnackBar();

    if (result.notConfigured) {
      messenger.showSnackBar(SnackBar(
        content: Text('$providerName is not configured yet — '
            'opening the share sheet instead'),
      ));
      await CloudExportService.shareViaSystemSheet(
        widget.filePath,
        subject: _documentTitle,
      );
      return;
    }
    if (result.cancelled) return;

    messenger.showSnackBar(SnackBar(
      content: Text(result.success
          ? 'Uploaded to $providerName'
          : 'Upload failed: ${result.error}'),
      action: result.success && result.remoteUrl != null
          ? SnackBarAction(
              label: 'Copy link',
              onPressed: () => Clipboard.setData(
                ClipboardData(text: result.remoteUrl!),
              ),
            )
          : null,
    ));
  }

  Future<void> _printPdf() async {
    final file = File(widget.filePath);
    if (!file.existsSync()) return;
    await Printing.layoutPdf(
      onLayout: (_) => file.readAsBytesSync(),
      name: _documentTitle,
    );
  }

  // ---------------------------------------------------------------------------
  // Overflow menu actions
  // ---------------------------------------------------------------------------

  void _onMenuAction(String action) {
    final encodedPath = Uri.encodeComponent(widget.filePath);
    switch (action) {
      case 'edit':
        context.push('/pdf-editor?path=$encodedPath');
      case 'annotate':
        context.push('/annotations?path=$encodedPath');
      case 'fill_sign':
        context.push('/fill-sign?path=$encodedPath');
      case 'share':
        _sharePdf();
      case 'print':
        _printPdf();
      case 'ocr':
        context.push('/ocr?path=$encodedPath');
      case 'convert':
        context.push('/convert');
      case 'compress':
        context.push('/compress-pdf?path=$encodedPath');
      case 'password':
        context.push('/password-protect?path=$encodedPath');
      case 'properties':
        _showProperties();
    }
  }

  Future<void> _showProperties() async {
    final file = File(widget.filePath);
    final stat = await file.stat();
    final sizeKb = (stat.size / 1024).toStringAsFixed(1);
    final sizeMb = (stat.size / (1024 * 1024)).toStringAsFixed(2);
    final sizeLabel = stat.size > 1024 * 1024 ? '$sizeMb MB' : '$sizeKb KB';

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Document Properties'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _propertyRow('Name', _documentTitle),
            _propertyRow('Size', sizeLabel),
            _propertyRow(
              'Modified',
              '${stat.modified.year}-'
                  '${stat.modified.month.toString().padLeft(2, '0')}-'
                  '${stat.modified.day.toString().padLeft(2, '0')}  '
                  '${stat.modified.hour.toString().padLeft(2, '0')}:'
                  '${stat.modified.minute.toString().padLeft(2, '0')}',
            ),
            _propertyRow(
              'Pages',
              ref.read(pdfViewerProvider).totalPages.toString(),
            ),
            _propertyRow(
              'Path',
              widget.filePath,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(AppStrings.ok),
          ),
        ],
      ),
    );
  }

  Widget _propertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final viewerState = ref.watch(pdfViewerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: _buildAppBar(viewerState, theme),
      body: Column(
        children: [
          // Inline search bar
          if (viewerState.isSearching) _buildSearchBar(theme),

          // PDF viewer
          Expanded(
            child: SfPdfViewer.file(
              File(widget.filePath),
              controller: _pdfController,
              canShowScrollHead: true,
              canShowScrollStatus: true,
              canShowPaginationDialog: false,
              enableDoubleTapZooming: true,
              enableTextSelection: true,
              onDocumentLoaded: (details) {
                ref
                    .read(pdfViewerProvider.notifier)
                    .setTotalPages(details.document.pages.count);
                ref.read(pdfViewerProvider.notifier).setPage(1);
              },
              onPageChanged: (details) {
                ref
                    .read(pdfViewerProvider.notifier)
                    .setPage(details.newPageNumber);
              },
            ),
          ),

          // Bottom toolbar
          _buildBottomToolbar(viewerState, theme),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // App bar
  // ---------------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar(PdfViewerState viewerState, ThemeData theme) {
    return AppBar(
      title: Text(
        _documentTitle,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        // Share shortcut
        IconButton(
          icon: const Icon(Icons.share_outlined),
          tooltip: AppStrings.share,
          onPressed: _sharePdf,
        ),
        // Overflow menu
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: _onMenuAction,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: _MenuRow(Icons.edit_outlined, 'Edit')),
            PopupMenuItem(value: 'annotate', child: _MenuRow(Icons.draw_outlined, 'Annotate')),
            PopupMenuItem(value: 'fill_sign', child: _MenuRow(Icons.gesture, 'Fill & Sign')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'share', child: _MenuRow(Icons.share_outlined, 'Share')),
            PopupMenuItem(value: 'print', child: _MenuRow(Icons.print_outlined, 'Print')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'ocr', child: _MenuRow(Icons.document_scanner_outlined, 'OCR')),
            PopupMenuItem(value: 'convert', child: _MenuRow(Icons.transform_outlined, 'Convert')),
            PopupMenuItem(value: 'compress', child: _MenuRow(Icons.compress_outlined, 'Compress')),
            PopupMenuItem(value: 'password', child: _MenuRow(Icons.lock_outline, 'Password Protect')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'properties', child: _MenuRow(Icons.info_outline, 'Properties')),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Inline search bar
  // ---------------------------------------------------------------------------

  Widget _buildSearchBar(ThemeData theme) {
    final hasResults = _searchResult != null && _searchResult!.totalInstanceCount > 0;
    final matchLabel = _searchResult != null && _searchResult!.totalInstanceCount > 0
        ? '${_searchResult!.currentInstanceIndex + 1} of ${_searchResult!.totalInstanceCount}'
        : _searchResult != null && _searchResult!.isSearchCompleted && _searchController.text.isNotEmpty
            ? 'No matches'
            : '';

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search in document...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _searchResult?.clear();
                          setState(() {});
                        },
                      )
                    : null,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onSubmitted: _startSearch,
              onChanged: (value) {
                if (value.isEmpty) {
                  _searchResult?.clear();
                  setState(() {});
                }
              },
            ),
          ),
          if (matchLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                matchLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          if (hasResults) ...[
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 22),
              tooltip: 'Previous match',
              onPressed: _previousMatch,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 22),
              tooltip: 'Next match',
              onPressed: _nextMatch,
              visualDensity: VisualDensity.compact,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 22),
            tooltip: 'Close search',
            onPressed: _clearSearch,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom toolbar
  // ---------------------------------------------------------------------------

  Widget _buildBottomToolbar(PdfViewerState viewerState, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 4,
        bottom: MediaQuery.of(context).padding.bottom + 4,
      ),
      child: Row(
        children: [
          // Page navigation
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous page',
            onPressed: viewerState.currentPage > 1
                ? () {
                    _pdfController.previousPage();
                  }
                : null,
          ),
          GestureDetector(
            onTap: _showGoToPageDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                viewerState.pageLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next page',
            onPressed:
                viewerState.currentPage < viewerState.totalPages
                    ? () {
                        _pdfController.nextPage();
                      }
                    : null,
          ),

          const Spacer(),

          // Zoom controls
          IconButton(
            icon: const Icon(Icons.zoom_out, size: 22),
            tooltip: 'Zoom out',
            onPressed: () {
              final newZoom = (_pdfController.zoomLevel - 0.25).clamp(1.0, 5.0);
              _pdfController.zoomLevel = newZoom;
              ref.read(pdfViewerProvider.notifier).setZoomLevel(newZoom);
            },
          ),
          Text(
            '${(_pdfController.zoomLevel * 100).round()}%',
            style: theme.textTheme.bodySmall,
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, size: 22),
            tooltip: 'Zoom in',
            onPressed: () {
              final newZoom = (_pdfController.zoomLevel + 0.25).clamp(1.0, 5.0);
              _pdfController.zoomLevel = newZoom;
              ref.read(pdfViewerProvider.notifier).setZoomLevel(newZoom);
            },
          ),

          const SizedBox(width: 4),

          // Search button
          IconButton(
            icon: Icon(
              viewerState.isSearching ? Icons.search_off : Icons.search,
              size: 22,
            ),
            tooltip: viewerState.isSearching ? 'Close search' : 'Search',
            onPressed: () {
              ref.read(pdfViewerProvider.notifier).toggleSearch();
              if (!viewerState.isSearching) {
                // Will open search bar; focus is handled by autofocus.
              } else {
                _clearSearch();
              }
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Go-to-page dialog
  // ---------------------------------------------------------------------------

  void _showGoToPageDialog() {
    final viewerState = ref.read(pdfViewerProvider);
    if (viewerState.totalPages == 0) return;

    final controller = TextEditingController(
      text: viewerState.currentPage.toString(),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to Page'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '1 - ${viewerState.totalPages}',
          ),
          onSubmitted: (value) {
            _navigateToPage(value, viewerState.totalPages);
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () {
              _navigateToPage(controller.text, viewerState.totalPages);
              Navigator.of(ctx).pop();
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  void _navigateToPage(String value, int totalPages) {
    final page = int.tryParse(value);
    if (page == null || page < 1 || page > totalPages) return;
    _pdfController.jumpToPage(page);
  }
}

// ---------------------------------------------------------------------------
// Small helper widget used inside the popup menu.
// ---------------------------------------------------------------------------

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuRow(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
