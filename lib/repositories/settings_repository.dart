import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/scan_settings_model.dart';

/// Enumerates the available sort orders for the document list.
enum SortPreference {
  modifiedDesc,
  modifiedAsc,
  titleAsc,
  titleDesc,
  sizeDesc,
  sizeAsc,
  createdDesc,
  createdAsc;

  String toJson() => name;

  static SortPreference fromJson(String value) {
    return SortPreference.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SortPreference.modifiedDesc,
    );
  }

  String get displayName {
    switch (this) {
      case SortPreference.modifiedDesc:
        return 'Last Modified (Newest)';
      case SortPreference.modifiedAsc:
        return 'Last Modified (Oldest)';
      case SortPreference.titleAsc:
        return 'Title (A-Z)';
      case SortPreference.titleDesc:
        return 'Title (Z-A)';
      case SortPreference.sizeDesc:
        return 'Size (Largest)';
      case SortPreference.sizeAsc:
        return 'Size (Smallest)';
      case SortPreference.createdDesc:
        return 'Date Created (Newest)';
      case SortPreference.createdAsc:
        return 'Date Created (Oldest)';
    }
  }
}

/// Enumerates the supported theme modes.
enum AppThemeMode {
  system,
  light,
  dark;

  String toJson() => name;

  static AppThemeMode fromJson(String value) {
    return AppThemeMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AppThemeMode.system,
    );
  }
}

/// Persists application-wide settings to a local `settings.json` file.
///
/// This is a lightweight alternative to SharedPreferences that keeps all
/// settings in a single, human-readable JSON document.
class SettingsRepository {
  static const String _fileName = 'settings.json';

  Map<String, dynamic>? _cache;

  // ---------------------------------------------------------------------------
  // Storage keys
  // ---------------------------------------------------------------------------
  static const String _keyThemeMode = 'themeMode';
  static const String _keyDefaultScanFilter = 'defaultScanFilter';
  static const String _keyOcrLanguages = 'ocrLanguages';
  static const String _keySortPreference = 'sortPreference';
  static const String _keyFirstLaunchDate = 'firstLaunchDate';
  static const String _keyIsProUser = 'isProUser';
  static const String _keyGridView = 'gridView';
  static const String _keyAutoBackup = 'autoBackup';
  static const String _keyScanSettings = 'scanSettings';
  static const String _keyLastSyncDate = 'lastSyncDate';
  static const String _keyNotificationsEnabled = 'notificationsEnabled';
  static const String _keyBiometricLockEnabled = 'biometricLockEnabled';
  static const String _keySessionCount = 'sessionCount';

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<File> _getStorageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<Map<String, dynamic>> _ensureLoaded({bool force = false}) async {
    if (_cache != null && !force) return _cache!;

    final file = await _getStorageFile();

    if (!await file.exists()) {
      _cache = _defaultSettings();
      await _flush();
      return _cache!;
    }

    try {
      final contents = await file.readAsString();
      _cache = json.decode(contents) as Map<String, dynamic>;
    } catch (_) {
      _cache = _defaultSettings();
    }

    return _cache!;
  }

  Future<void> _flush() async {
    final file = await _getStorageFile();
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(_cache));
  }

  Map<String, dynamic> _defaultSettings() {
    return {
      _keyThemeMode: AppThemeMode.system.toJson(),
      _keyDefaultScanFilter: ScanFilter.enhanced.toJson(),
      _keyOcrLanguages: <String>['en'],
      _keySortPreference: SortPreference.modifiedDesc.toJson(),
      _keyFirstLaunchDate: DateTime.now().toIso8601String(),
      _keyIsProUser: false,
      _keyGridView: true,
      _keyAutoBackup: false,
      _keyScanSettings: const ScanSettingsModel().toJson(),
      _keyLastSyncDate: null,
      _keyNotificationsEnabled: true,
      _keyBiometricLockEnabled: false,
      _keySessionCount: 0,
    };
  }

  // ---------------------------------------------------------------------------
  // Generic get / set
  // ---------------------------------------------------------------------------

  /// Reads a raw value by [key].
  Future<T?> getValue<T>(String key) async {
    final data = await _ensureLoaded();
    return data[key] as T?;
  }

  /// Writes a raw [value] for [key] and flushes to disk.
  Future<void> setValue<T>(String key, T value) async {
    final data = await _ensureLoaded();
    data[key] = value;
    await _flush();
  }

  // ---------------------------------------------------------------------------
  // Theme
  // ---------------------------------------------------------------------------

  Future<AppThemeMode> getThemeMode() async {
    final data = await _ensureLoaded();
    return AppThemeMode.fromJson(data[_keyThemeMode] as String? ?? 'system');
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    await setValue(_keyThemeMode, mode.toJson());
  }

  // ---------------------------------------------------------------------------
  // Default scan filter
  // ---------------------------------------------------------------------------

  Future<ScanFilter> getDefaultScanFilter() async {
    final data = await _ensureLoaded();
    return ScanFilter.fromJson(
        data[_keyDefaultScanFilter] as String? ?? 'enhanced');
  }

  Future<void> setDefaultScanFilter(ScanFilter filter) async {
    await setValue(_keyDefaultScanFilter, filter.toJson());
  }

  // ---------------------------------------------------------------------------
  // OCR languages
  // ---------------------------------------------------------------------------

  Future<List<String>> getOcrLanguages() async {
    final data = await _ensureLoaded();
    final raw = data[_keyOcrLanguages];
    if (raw is List) {
      return raw.cast<String>();
    }
    return ['en'];
  }

  Future<void> setOcrLanguages(List<String> languages) async {
    await setValue(_keyOcrLanguages, languages);
  }

  // ---------------------------------------------------------------------------
  // Sort preference
  // ---------------------------------------------------------------------------

  Future<SortPreference> getSortPreference() async {
    final data = await _ensureLoaded();
    return SortPreference.fromJson(
        data[_keySortPreference] as String? ?? 'modifiedDesc');
  }

  Future<void> setSortPreference(SortPreference pref) async {
    await setValue(_keySortPreference, pref.toJson());
  }

  // ---------------------------------------------------------------------------
  // First launch date
  // ---------------------------------------------------------------------------

  Future<DateTime> getFirstLaunchDate() async {
    final data = await _ensureLoaded();
    final raw = data[_keyFirstLaunchDate] as String?;
    if (raw != null) return DateTime.parse(raw);
    final now = DateTime.now();
    await setValue(_keyFirstLaunchDate, now.toIso8601String());
    return now;
  }

  // ---------------------------------------------------------------------------
  // Session counter (used by ad rules: banners only from session 2 onward)
  // ---------------------------------------------------------------------------

  Future<int> getSessionCount() async {
    final data = await _ensureLoaded();
    return (data[_keySessionCount] as num?)?.toInt() ?? 0;
  }

  Future<void> setSessionCount(int count) async {
    await setValue(_keySessionCount, count);
  }

  // ---------------------------------------------------------------------------
  // Pro status
  // ---------------------------------------------------------------------------

  Future<bool> isProUser() async {
    final data = await _ensureLoaded();
    return data[_keyIsProUser] as bool? ?? false;
  }

  Future<void> setProUser(bool value) async {
    await setValue(_keyIsProUser, value);
  }

  // ---------------------------------------------------------------------------
  // Grid view toggle
  // ---------------------------------------------------------------------------

  Future<bool> isGridView() async {
    final data = await _ensureLoaded();
    return data[_keyGridView] as bool? ?? true;
  }

  Future<void> setGridView(bool value) async {
    await setValue(_keyGridView, value);
  }

  // ---------------------------------------------------------------------------
  // Auto backup
  // ---------------------------------------------------------------------------

  Future<bool> isAutoBackupEnabled() async {
    final data = await _ensureLoaded();
    return data[_keyAutoBackup] as bool? ?? false;
  }

  Future<void> setAutoBackup(bool value) async {
    await setValue(_keyAutoBackup, value);
  }

  // ---------------------------------------------------------------------------
  // Scan settings
  // ---------------------------------------------------------------------------

  Future<ScanSettingsModel> getScanSettings() async {
    final data = await _ensureLoaded();
    final raw = data[_keyScanSettings];
    if (raw is Map<String, dynamic>) {
      return ScanSettingsModel.fromJson(raw);
    }
    return const ScanSettingsModel();
  }

  Future<void> setScanSettings(ScanSettingsModel settings) async {
    await setValue(_keyScanSettings, settings.toJson());
  }

  // ---------------------------------------------------------------------------
  // Last sync date
  // ---------------------------------------------------------------------------

  Future<DateTime?> getLastSyncDate() async {
    final data = await _ensureLoaded();
    final raw = data[_keyLastSyncDate] as String?;
    return raw != null ? DateTime.parse(raw) : null;
  }

  Future<void> setLastSyncDate(DateTime date) async {
    await setValue(_keyLastSyncDate, date.toIso8601String());
  }

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  Future<bool> areNotificationsEnabled() async {
    final data = await _ensureLoaded();
    return data[_keyNotificationsEnabled] as bool? ?? true;
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await setValue(_keyNotificationsEnabled, value);
  }

  // ---------------------------------------------------------------------------
  // Biometric lock
  // ---------------------------------------------------------------------------

  Future<bool> isBiometricLockEnabled() async {
    final data = await _ensureLoaded();
    return data[_keyBiometricLockEnabled] as bool? ?? false;
  }

  Future<void> setBiometricLockEnabled(bool value) async {
    await setValue(_keyBiometricLockEnabled, value);
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  /// Resets all settings to their defaults and flushes to disk.
  ///
  /// Install-tracking values (first launch date, session count) are kept so
  /// a settings reset cannot re-grant the new-user ad grace period.
  Future<void> resetToDefaults() async {
    final previous = await _ensureLoaded();
    _cache = _defaultSettings()
      ..[_keyFirstLaunchDate] =
          previous[_keyFirstLaunchDate] ?? DateTime.now().toIso8601String()
      ..[_keySessionCount] = previous[_keySessionCount] ?? 0;
    await _flush();
  }

  /// Forces a reload from disk on the next access.
  void invalidateCache() {
    _cache = null;
  }
}
