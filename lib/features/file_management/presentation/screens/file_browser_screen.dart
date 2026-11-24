import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/storage_service.dart';
import 'package:docuscan_pro/core/widgets/ad_banner_widget.dart';
import 'package:docuscan_pro/core/widgets/document_thumbnail.dart';
import 'package:docuscan_pro/core/widgets/empty_state_widget.dart';
import 'package:docuscan_pro/features/home/presentation/providers/home_provider.dart';
import 'package:docuscan_pro/models/document_model.dart';

class FileBrowserScreen extends ConsumerStatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isGridView = true;
  String _sortBy = 'date_desc';
  List<DocumentModel> _documents = [];
  List<DocumentModel> _filteredDocuments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(documentRepositoryProvider);
      final docs = await repo.getAll();
      _sortDocuments(docs);
      setState(() {
        _documents = docs;
        _filteredDocuments = docs;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _sortDocuments(List<DocumentModel> docs) {
    switch (_sortBy) {
      case 'date_desc':
        docs.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      case 'date_asc':
        docs.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
      case 'name_asc':
        docs.sort((a, b) => a.title.compareTo(b.title));
      case 'name_desc':
        docs.sort((a, b) => b.title.compareTo(a.title));
      case 'size_desc':
        docs.sort((a, b) => b.fileSize.compareTo(a.fileSize));
      case 'size_asc':
        docs.sort((a, b) => a.fileSize.compareTo(b.fileSize));
    }
  }

  void _onSearch(String query) {
    if (query.isEmpty) {
      setState(() => _filteredDocuments = _documents);
    } else {
      setState(() {
        _filteredDocuments = _documents
            .where((d) => d.title.toLowerCase().contains(query.toLowerCase()))
            .toList();
      });
    }
  }

  Future<void> _importFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (picked.isEmpty) return;

    for (final file in picked) {
      if (file.path == null) continue;
      final doc = await DocumentModel.createFromFile(File(file.path!));
      final repo = ref.read(documentRepositoryProvider);
      await repo.save(doc);
    }

    _loadDocuments();
  }

  Future<void> _deleteDocument(DocumentModel doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.delete),
        content: Text('Delete "${doc.title}"? This cannot be undone.'),
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

    final repo = ref.read(documentRepositoryProvider);
    await repo.delete(doc.id);

    // Delete file from disk
    final file = File(doc.filePath);
    if (await file.exists()) await file.delete();

    _loadDocuments();
  }

  Future<void> _renameDocument(DocumentModel doc) async {
    final controller = TextEditingController(text: doc.title);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.rename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text(AppStrings.save),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    final repo = ref.read(documentRepositoryProvider);
    await repo.update(doc.copyWith(title: newName));
    _loadDocuments();
  }

  void _openDocument(DocumentModel doc) {
    context.push('/pdf-viewer?path=${Uri.encodeComponent(doc.filePath)}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSearching
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchController.clear();
                    _filteredDocuments = _documents;
                  });
                },
              ),
              title: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  hintText: AppStrings.searchDocuments,
                  border: InputBorder.none,
                ),
              ),
            )
          : AppBar(
              title: const Text(AppStrings.myDocuments),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() => _isSearching = true),
                ),
                IconButton(
                  icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort),
                  onSelected: (value) {
                    setState(() {
                      _sortBy = value;
                      _sortDocuments(_filteredDocuments);
                    });
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'date_desc', child: Text('Newest First')),
                    const PopupMenuItem(value: 'date_asc', child: Text('Oldest First')),
                    const PopupMenuItem(value: 'name_asc', child: Text('Name A-Z')),
                    const PopupMenuItem(value: 'name_desc', child: Text('Name Z-A')),
                    const PopupMenuItem(value: 'size_desc', child: Text('Largest First')),
                    const PopupMenuItem(value: 'size_asc', child: Text('Smallest First')),
                  ],
                ),
              ],
            ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredDocuments.isEmpty
                    ? EmptyStateWidget(
                        icon: Icons.folder_open,
                        title: _searchController.text.isNotEmpty
                            ? AppStrings.noResults
                            : AppStrings.emptyFolder,
                        subtitle: 'Import or scan documents to get started',
                        actionLabel: 'Import File',
                        onAction: _importFile,
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDocuments,
                        child: _isGridView
                            ? _buildGridView()
                            : _buildListView(),
                      ),
          ),
          const AdBannerWidget(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importFile,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: _filteredDocuments.length,
      itemBuilder: (context, index) {
        final doc = _filteredDocuments[index];
        return _DocumentGridItem(
          document: doc,
          onTap: () => _openDocument(doc),
          onRename: () => _renameDocument(doc),
          onDelete: () => _deleteDocument(doc),
          onShare: () => SharePlus.instance.share(ShareParams(files: [XFile(doc.filePath)])),
        );
      },
    );
  }

  Widget _buildListView() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredDocuments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final doc = _filteredDocuments[index];
        return _DocumentListItem(
          document: doc,
          onTap: () => _openDocument(doc),
          onRename: () => _renameDocument(doc),
          onDelete: () => _deleteDocument(doc),
          onShare: () => SharePlus.instance.share(ShareParams(files: [XFile(doc.filePath)])),
        );
      },
    );
  }
}

class _DocumentGridItem extends StatelessWidget {
  final DocumentModel document;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const _DocumentGridItem({
    required this.document,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  DocumentThumbnail(
                    filePath: document.filePath,
                    thumbnailPath: document.thumbnailPath,
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: 12,
                    pageCount: document.pageCount,
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: PopupMenuButton<String>(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.more_vert,
                            color: Colors.white, size: 16),
                      ),
                      onSelected: (v) {
                        switch (v) {
                          case 'rename':
                            onRename();
                          case 'delete':
                            onDelete();
                          case 'share':
                            onShare();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'share', child: Text('Share')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                  if (document.isPasswordProtected)
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: Icon(Icons.lock, size: 16, color: Colors.white),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${StorageService.formatFileSize(document.fileSize)} - ${document.pageCount} pages',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentListItem extends StatelessWidget {
  final DocumentModel document;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const _DocumentListItem({
    required this.document,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: SizedBox(
          width: 44,
          height: 56,
          child: DocumentThumbnail(
            filePath: document.filePath,
            thumbnailPath: document.thumbnailPath,
            width: 44,
            height: 56,
            borderRadius: 6,
            pageCount: document.pageCount,
          ),
        ),
        title: Text(
          document.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${StorageService.formatFileSize(document.fileSize)} - ${document.pageCount} pages',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'rename':
                onRename();
              case 'delete':
                onDelete();
              case 'share':
                onShare();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'share', child: Text('Share')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
