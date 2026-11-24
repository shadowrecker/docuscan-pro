import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:docuscan_pro/models/scan_settings_model.dart';
import 'package:docuscan_pro/repositories/settings_repository.dart';

// ---------------------------------------------------------------------------
// Repository provider
// ---------------------------------------------------------------------------

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

// ---------------------------------------------------------------------------
// Settings state
// ---------------------------------------------------------------------------

/// Immutable snapshot of all user-configurable settings.
class SettingsState {
  final ThemeMode themeMode;
  final ScanFilter defaultScanFilter;
  final List<String> ocrLanguages;
  final SortPreference sortPreference;
  final bool isProUser;
  final bool autoEdgeDetection;

  /// The language used by the OCR screen: the first entry of [ocrLanguages].
  String get primaryOcrLanguage =>
      ocrLanguages.isEmpty ? 'en' : ocrLanguages.first;

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.defaultScanFilter = ScanFilter.enhanced,
    this.ocrLanguages = const ['en'],
    this.sortPreference = SortPreference.modifiedDesc,
    this.isProUser = false,
    this.autoEdgeDetection = true,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    ScanFilter? defaultScanFilter,
    List<String>? ocrLanguages,
    SortPreference? sortPreference,
    bool? isProUser,
    bool? autoEdgeDetection,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      defaultScanFilter: defaultScanFilter ?? this.defaultScanFilter,
      ocrLanguages: ocrLanguages ?? this.ocrLanguages,
      sortPreference: sortPreference ?? this.sortPreference,
      isProUser: isProUser ?? this.isProUser,
      autoEdgeDetection: autoEdgeDetection ?? this.autoEdgeDetection,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsState &&
          runtimeType == other.runtimeType &&
          themeMode == other.themeMode &&
          defaultScanFilter == other.defaultScanFilter &&
          sortPreference == other.sortPreference &&
          isProUser == other.isProUser &&
          autoEdgeDetection == other.autoEdgeDetection &&
          _listEquals(ocrLanguages, other.ocrLanguages);

  @override
  int get hashCode => Object.hash(
        themeMode,
        defaultScanFilter,
        Object.hashAll(ocrLanguages),
        sortPreference,
        isProUser,
        autoEdgeDetection,
      );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Settings notifier
// ---------------------------------------------------------------------------

class SettingsNotifier extends StateNotifier<SettingsState> {
  final SettingsRepository _repository;

  SettingsNotifier(this._repository) : super(const SettingsState()) {
    _loadFromDisk();
  }

  /// Reads persisted settings and updates state once loaded.
  Future<void> _loadFromDisk() async {
    final themeMode = await _repository.getThemeMode();
    final filter = await _repository.getDefaultScanFilter();
    final languages = await _repository.getOcrLanguages();
    final sortPref = await _repository.getSortPreference();
    final isPro = await _repository.isProUser();
    final scanSettings = await _repository.getScanSettings();

    state = SettingsState(
      themeMode: _mapAppThemeMode(themeMode),
      defaultScanFilter: filter,
      ocrLanguages: languages,
      sortPreference: sortPref,
      isProUser: isPro,
      autoEdgeDetection: scanSettings.autoEdgeDetection,
    );
  }

  // -------------------------------------------------------------------------
  // Public mutations
  // -------------------------------------------------------------------------

  /// Toggles between light and dark mode. If the current mode is system,
  /// it resolves to dark first.
  void toggleTheme() {
    final next = state.themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    setThemeMode(next);
  }

  /// Sets the theme to a specific [ThemeMode].
  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _repository.setThemeMode(_mapThemeMode(mode));
  }

  /// Updates the default scan filter applied to new scans.
  void setDefaultScanFilter(ScanFilter filter) {
    state = state.copyWith(defaultScanFilter: filter);
    _repository.setDefaultScanFilter(filter);
  }

  /// Adds or removes [language] from the selected OCR languages.
  void toggleOcrLanguage(String language) {
    final current = List<String>.from(state.ocrLanguages);
    if (current.contains(language)) {
      // Ensure at least one language remains selected.
      if (current.length > 1) {
        current.remove(language);
      }
    } else {
      current.add(language);
    }
    state = state.copyWith(ocrLanguages: current);
    _repository.setOcrLanguages(current);
  }

  /// Makes [language] the primary OCR language (used by the OCR screen),
  /// keeping any other selected languages after it.
  void setPrimaryOcrLanguage(String language) {
    final updated = [
      language,
      ...state.ocrLanguages.where((l) => l != language),
    ];
    state = state.copyWith(ocrLanguages: updated);
    _repository.setOcrLanguages(updated);
  }

  /// Enables/disables automatic document edge detection for new scans.
  Future<void> setAutoEdgeDetection(bool value) async {
    state = state.copyWith(autoEdgeDetection: value);
    final scan = await _repository.getScanSettings();
    await _repository
        .setScanSettings(scan.copyWith(autoEdgeDetection: value));
  }

  /// Updates the document sort preference.
  void setSortPreference(SortPreference preference) {
    state = state.copyWith(sortPreference: preference);
    _repository.setSortPreference(preference);
  }

  /// Updates the pro-user status (e.g. after a successful purchase).
  void setProUser(bool value) {
    state = state.copyWith(isProUser: value);
    _repository.setProUser(value);
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static ThemeMode _mapAppThemeMode(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  static AppThemeMode _mapThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return AppThemeMode.light;
      case ThemeMode.dark:
        return AppThemeMode.dark;
      case ThemeMode.system:
        return AppThemeMode.system;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final repository = ref.watch(settingsRepositoryProvider);
  return SettingsNotifier(repository);
});
