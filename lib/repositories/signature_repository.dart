import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/signature_model.dart';

/// Persists [SignatureModel] instances to a local `signatures.json` file.
class SignatureRepository {
  static const String _fileName = 'signatures.json';

  /// In-memory cache, keyed by signature id.
  Map<String, SignatureModel>? _cache;

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<File> _getStorageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<Map<String, SignatureModel>> _ensureLoaded(
      {bool force = false}) async {
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
              SignatureModel.fromJson(item),
      };
    } catch (_) {
      _cache = {};
    }

    return _cache!;
  }

  Future<void> _flush() async {
    final file = await _getStorageFile();
    final jsonList = _cache!.values.map((s) => s.toJson()).toList();
    await file.writeAsString(json.encode(jsonList));
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns all saved signatures, ordered by [createdAt] descending.
  Future<List<SignatureModel>> getAll() async {
    final cache = await _ensureLoaded();
    final list = cache.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Persists a new signature. If this is the first signature it is
  /// automatically marked as the default.
  Future<void> save(SignatureModel signature) async {
    final cache = await _ensureLoaded();

    // First signature becomes the default automatically.
    final isFirst = cache.isEmpty;
    final toSave = isFirst ? signature.copyWith(isDefault: true) : signature;

    cache[toSave.id] = toSave;
    await _flush();
  }

  /// Deletes the signature with the given [id].
  ///
  /// If the deleted signature was the default, the most recently created
  /// remaining signature is promoted to default.
  Future<void> delete(String id) async {
    final cache = await _ensureLoaded();
    final removed = cache.remove(id);
    if (removed == null) return;

    // Promote a new default if needed.
    if (removed.isDefault && cache.isNotEmpty) {
      final sorted = cache.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final newDefault = sorted.first.copyWith(isDefault: true);
      cache[newDefault.id] = newDefault;
    }

    await _flush();
  }

  /// Returns the current default signature, or `null` if none exists.
  Future<SignatureModel?> getDefault() async {
    final cache = await _ensureLoaded();
    try {
      return cache.values.firstWhere((s) => s.isDefault);
    } catch (_) {
      return null;
    }
  }

  /// Sets the signature identified by [id] as the default, clearing the flag
  /// on all others.
  Future<void> setDefault(String id) async {
    final cache = await _ensureLoaded();

    if (!cache.containsKey(id)) {
      throw StateError(
        'Cannot set default – signature "$id" not found in repository.',
      );
    }

    for (final entry in cache.entries.toList()) {
      cache[entry.key] = entry.value.copyWith(
        isDefault: entry.key == id,
      );
    }

    await _flush();
  }

  /// Forces a reload from disk on the next access.
  void invalidateCache() {
    _cache = null;
  }
}
