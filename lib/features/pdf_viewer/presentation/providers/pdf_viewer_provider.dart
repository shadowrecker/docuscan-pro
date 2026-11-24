import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class PdfViewerState {
  final int currentPage;
  final int totalPages;
  final bool isSearching;
  final String searchQuery;
  final List<PdfSearchMatch> searchResults;
  final int currentSearchIndex;
  final double zoomLevel;

  const PdfViewerState({
    this.currentPage = 1,
    this.totalPages = 0,
    this.isSearching = false,
    this.searchQuery = '',
    this.searchResults = const [],
    this.currentSearchIndex = -1,
    this.zoomLevel = 1.0,
  });

  PdfViewerState copyWith({
    int? currentPage,
    int? totalPages,
    bool? isSearching,
    String? searchQuery,
    List<PdfSearchMatch>? searchResults,
    int? currentSearchIndex,
    double? zoomLevel,
  }) {
    return PdfViewerState(
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      isSearching: isSearching ?? this.isSearching,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
      currentSearchIndex: currentSearchIndex ?? this.currentSearchIndex,
      zoomLevel: zoomLevel ?? this.zoomLevel,
    );
  }

  /// Human-readable page label: "Page 3 of 12".
  String get pageLabel =>
      totalPages > 0 ? 'Page $currentPage of $totalPages' : '';

  bool get hasNextMatch =>
      searchResults.isNotEmpty &&
      currentSearchIndex < searchResults.length - 1;

  bool get hasPreviousMatch =>
      searchResults.isNotEmpty && currentSearchIndex > 0;
}

// ---------------------------------------------------------------------------
// Simple model for a search match (page + instance index)
// ---------------------------------------------------------------------------

class PdfSearchMatch {
  final int pageIndex;
  final int matchIndex;

  const PdfSearchMatch({required this.pageIndex, required this.matchIndex});
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class PdfViewerNotifier extends StateNotifier<PdfViewerState> {
  PdfViewerNotifier() : super(const PdfViewerState());

  // -- Page navigation -------------------------------------------------------

  void setPage(int page) {
    if (page < 1 || (state.totalPages > 0 && page > state.totalPages)) return;
    state = state.copyWith(currentPage: page);
  }

  void setTotalPages(int total) {
    state = state.copyWith(totalPages: total);
  }

  void nextPage() {
    if (state.currentPage < state.totalPages) {
      state = state.copyWith(currentPage: state.currentPage + 1);
    }
  }

  void previousPage() {
    if (state.currentPage > 1) {
      state = state.copyWith(currentPage: state.currentPage - 1);
    }
  }

  // -- Search ----------------------------------------------------------------

  void toggleSearch() {
    final opening = !state.isSearching;
    state = state.copyWith(
      isSearching: opening,
      searchQuery: opening ? state.searchQuery : '',
      searchResults: opening ? state.searchResults : const [],
      currentSearchIndex: opening ? state.currentSearchIndex : -1,
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(
      searchQuery: query,
      // Reset results when query changes; actual search is driven from the UI
      // via the SfPdfViewer searchText API.
      currentSearchIndex: -1,
    );
  }

  void setSearchResults(List<PdfSearchMatch> results) {
    state = state.copyWith(
      searchResults: results,
      currentSearchIndex: results.isNotEmpty ? 0 : -1,
    );
  }

  void nextSearchMatch() {
    if (state.hasNextMatch) {
      state = state.copyWith(currentSearchIndex: state.currentSearchIndex + 1);
    }
  }

  void previousSearchMatch() {
    if (state.hasPreviousMatch) {
      state = state.copyWith(currentSearchIndex: state.currentSearchIndex - 1);
    }
  }

  // -- Zoom ------------------------------------------------------------------

  void setZoomLevel(double level) {
    final clamped = level.clamp(0.5, 5.0);
    state = state.copyWith(zoomLevel: clamped);
  }

  void zoomIn() => setZoomLevel(state.zoomLevel + 0.25);
  void zoomOut() => setZoomLevel(state.zoomLevel - 0.25);

  // -- Reset -----------------------------------------------------------------

  void reset() {
    state = const PdfViewerState();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final pdfViewerProvider =
    StateNotifierProvider.autoDispose<PdfViewerNotifier, PdfViewerState>(
  (ref) => PdfViewerNotifier(),
);
