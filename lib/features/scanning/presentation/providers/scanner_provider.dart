import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:docuscan_pro/features/scanning/presentation/screens/scanner_screen.dart';
import 'package:docuscan_pro/models/scan_settings_model.dart';
import 'package:docuscan_pro/core/utils/image_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Scanner State
// ─────────────────────────────────────────────────────────────────────────────

class ScannerState {
  final List<String> capturedImages;
  final ScanFilter currentFilter;
  final bool isProcessing;
  final ScanMode scanMode;
  final int currentPageIndex;

  const ScannerState({
    this.capturedImages = const [],
    this.currentFilter = ScanFilter.original,
    this.isProcessing = false,
    this.scanMode = ScanMode.document,
    this.currentPageIndex = 0,
  });

  ScannerState copyWith({
    List<String>? capturedImages,
    ScanFilter? currentFilter,
    bool? isProcessing,
    ScanMode? scanMode,
    int? currentPageIndex,
  }) {
    return ScannerState(
      capturedImages: capturedImages ?? this.capturedImages,
      currentFilter: currentFilter ?? this.currentFilter,
      isProcessing: isProcessing ?? this.isProcessing,
      scanMode: scanMode ?? this.scanMode,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
    );
  }

  int get pageCount => capturedImages.length;

  bool get hasImages => capturedImages.isNotEmpty;

  /// Returns the path of the currently selected page, or `null` when the list
  /// is empty.
  String? get currentImagePath {
    if (capturedImages.isEmpty) return null;
    final clamped = currentPageIndex.clamp(0, capturedImages.length - 1);
    return capturedImages[clamped];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScannerState &&
          runtimeType == other.runtimeType &&
          capturedImages == other.capturedImages &&
          currentFilter == other.currentFilter &&
          isProcessing == other.isProcessing &&
          scanMode == other.scanMode &&
          currentPageIndex == other.currentPageIndex;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(capturedImages),
        currentFilter,
        isProcessing,
        scanMode,
        currentPageIndex,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Scanner Notifier
// ─────────────────────────────────────────────────────────────────────────────

class ScannerNotifier extends StateNotifier<ScannerState> {
  ScannerNotifier() : super(const ScannerState());

  /// Appends a newly captured image path and advances the page index.
  void addImage(String path) {
    final updated = [...state.capturedImages, path];
    state = state.copyWith(
      capturedImages: updated,
      currentPageIndex: updated.length - 1,
    );
  }

  /// Removes the image at [index] and adjusts the current page index.
  void removeImage(int index) {
    if (index < 0 || index >= state.capturedImages.length) return;
    final updated = [...state.capturedImages]..removeAt(index);
    final newIndex = updated.isEmpty
        ? 0
        : state.currentPageIndex.clamp(0, updated.length - 1);
    state = state.copyWith(
      capturedImages: updated,
      currentPageIndex: newIndex,
    );
  }

  /// Sets the active filter type.
  void setFilter(ScanFilter filter) {
    state = state.copyWith(currentFilter: filter);
  }

  /// Applies the current filter to every captured image, writing the result
  /// back to disk in-place. The [isProcessing] flag is set while work is
  /// in progress.
  Future<void> applyFilterToAll() async {
    if (state.capturedImages.isEmpty) return;
    if (state.currentFilter == ScanFilter.original) return;

    state = state.copyWith(isProcessing: true);

    try {
      final updatedPaths = <String>[];

      for (final path in state.capturedImages) {
        final bytes = await File(path).readAsBytes();
        final Uint8List processed;

        switch (state.currentFilter) {
          case ScanFilter.enhanced:
            processed = await ImageUtils.applyEnhancedFilter(bytes);
            break;
          case ScanFilter.grayscale:
            processed = await ImageUtils.applyGrayscaleFilter(bytes);
            break;
          case ScanFilter.bw:
            processed = await ImageUtils.applyBWFilter(bytes);
            break;
          case ScanFilter.original:
            processed = bytes;
            break;
        }

        await File(path).writeAsBytes(processed);
        updatedPaths.add(path);
      }

      state = state.copyWith(
        capturedImages: updatedPaths,
        isProcessing: false,
      );
    } catch (_) {
      state = state.copyWith(isProcessing: false);
      rethrow;
    }
  }

  /// Updates the scan mode (document / whiteboard).
  void setMode(ScanMode mode) {
    state = state.copyWith(scanMode: mode);
  }

  /// Replaces the image at [currentPageIndex] with a newly captured [path].
  void retakeImage(String path) {
    if (state.capturedImages.isEmpty) return;
    final index = state.currentPageIndex.clamp(0, state.capturedImages.length - 1);
    final updated = [...state.capturedImages];
    updated[index] = path;
    state = state.copyWith(capturedImages: updated);
  }

  /// Rotates the current page image 90 degrees clockwise and writes the result
  /// back to disk.
  Future<void> rotateCurrent() async {
    final path = state.currentImagePath;
    if (path == null) return;

    state = state.copyWith(isProcessing: true);
    try {
      final bytes = await File(path).readAsBytes();
      final rotated = await ImageUtils.rotateImage(bytes, 90);
      await File(path).writeAsBytes(rotated);

      // Force state update so listeners rebuild with the new image data.
      state = state.copyWith(
        capturedImages: [...state.capturedImages],
        isProcessing: false,
      );
    } catch (_) {
      state = state.copyWith(isProcessing: false);
      rethrow;
    }
  }

  /// Moves the page-view index to the given [index].
  void setCurrentPageIndex(int index) {
    state = state.copyWith(currentPageIndex: index);
  }

  /// Resets all state back to defaults.
  void clear() {
    state = const ScannerState();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Riverpod Provider
// ─────────────────────────────────────────────────────────────────────────────

final scannerProvider =
    StateNotifierProvider<ScannerNotifier, ScannerState>((ref) {
  return ScannerNotifier();
});
