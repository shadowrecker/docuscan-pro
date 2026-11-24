import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/document_model.dart';

/// Persists [DocumentModel] instances to a local `documents.json` file.
///
/// All mutations are immediately flushed to disk so data survives app restarts.
/// An in-memory cache is maintained after the first load to keep reads fast.
class DocumentRepository {
  static const String _fileName = 'documents.json';

  /// In-memory cache, keyed by document id.
  Map<String, DocumentModel>? _cache;

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Resolves the full path to the backing JSON file.
  Future<File> _getStorageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  /// Loads documents from disk into [_cache]. Subsequent calls are no-ops
  /// unless [force] is `true`.
  Future<Map<String, DocumentModel>> _ensureLoaded({bool force = false}) async {
    if (_cache != null && !force) return _cache!;

    final file = await _getStorageFile();

    if (!await file.exists()) {
      _cache = {};
      return _cache!;
    }

    try {
      final contents = await file.readAsString();
      final List<dynamic> jsonList = json.decode(contents) as List<dynamic>;
      _cache = {
        for (final item in jsonList)
          (item as Map<String, dynamic>)['id'] as String:
              DocumentModel.fromJson(item),
      };
    } catch (_) {
      // Corrupted file – start fresh rather than crash.
      _cache = {};
    }

    return _cache!;
  }

  /// Writes the current [_cache] to disk.
  Future<void> _flush() async {
    final file = await _getStorageFile();
    final jsonList = _cache!.values.map((d) => d.toJson()).toList();
    await file.writeAsString(json.encode(jsonList));
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns all stored documents, ordered by [modifiedAt] descending.
  Future<List<DocumentModel>> getAll() async {
    final cache = await _ensureLoaded();
    final docs = cache.values.toList()
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return docs;
  }

  /// Returns a single document by [id], or `null` if not found.
  Future<DocumentModel?> getById(String id) async {
    final cache = await _ensureLoaded();
    return cache[id];
  }

  /// Returns the [limit] most recently modified documents.
  Future<List<DocumentModel>> getRecent(int limit) async {
    final all = await getAll();
    return all.take(limit).toList();
  }

  /// Searches documents whose [title], [tags], or [ocrText] contain [query]
  /// (case-insensitive).
  Future<List<DocumentModel>> search(String query) async {
    if (query.trim().isEmpty) return getAll();

    final cache = await _ensureLoaded();
    final lower = query.toLowerCase();

    return cache.values.where((doc) {
      if (doc.title.toLowerCase().contains(lower)) return true;
      if (doc.tags.any((t) => t.toLowerCase().contains(lower))) return true;
      if (doc.ocrText != null && doc.ocrText!.toLowerCase().contains(lower)) {
        return true;
      }
      return false;
    }).toList()
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
  }

  /// Persists a new document. If a document with the same [id] already exists
  /// it will be overwritten (use [update] for explicit intent).
  Future<void> save(DocumentModel document) async {
    final cache = await _ensureLoaded();
    cache[document.id] = document;
    await _flush();
  }

  /// Registers a newly produced file (merge output, searchable PDF, …) as a
  /// document so it shows up in Recent and the file browser.
  Future<DocumentModel> saveOutputFile(
    String filePath, {
    String? title,
    int pageCount = 1,
    String? ocrText,
  }) async {
    final doc = await DocumentModel.createFromFile(
      File(filePath),
      title: title,
      pageCount: pageCount,
    );
    final withText = ocrText == null ? doc : doc.copyWith(ocrText: ocrText);
    await save(withText);
    return withText;
  }

  /// Updates an existing document. The [modifiedAt] timestamp is automatically
  /// set to now unless the caller has already done so.
  Future<void> update(DocumentModel document) async {
    final cache = await _ensureLoaded();
    if (!cache.containsKey(document.id)) {
      throw StateError(
        'Cannot update document "${document.id}" – not found in repository.',
      );
    }
    cache[document.id] = document.copyWith(modifiedAt: DateTime.now());
    await _flush();
  }

  /// Deletes the document with the given [id]. No-op if it does not exist.
  Future<void> delete(String id) async {
    final cache = await _ensureLoaded();
    if (cache.remove(id) != null) {
      await _flush();
    }
  }

  /// Returns all documents that belong to the folder identified by [folderId].
  Future<List<DocumentModel>> getByFolder(String folderId) async {
    final cache = await _ensureLoaded();
    return cache.values
        .where((doc) => doc.parentFolderId == folderId)
        .toList()
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
  }

  /// Returns the total number of stored documents.
  Future<int> getDocumentCount() async {
    final cache = await _ensureLoaded();
    return cache.length;
  }

  /// Returns the sum of [fileSize] across all stored documents (in bytes).
  Future<int> getTotalSize() async {
    final cache = await _ensureLoaded();
    return cache.values.fold<int>(0, (sum, doc) => sum + doc.fileSize);
  }

  /// Forces a reload from disk on the next access. Useful after external
  /// file-level changes (e.g. restore from backup).
  void invalidateCache() {
    _cache = null;
  }
}
