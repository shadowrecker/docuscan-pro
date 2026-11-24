import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:docuscan_pro/models/annotation_model.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class PdfEditorState {
  final List<AnnotationModel> annotations;
  final AnnotationType? currentTool;
  final Color currentColor;
  final double strokeWidth;
  final List<List<AnnotationModel>> undoStack;
  final List<List<AnnotationModel>> redoStack;
  final bool isModified;
  final bool isProcessing;
  final int currentPageIndex;

  const PdfEditorState({
    this.annotations = const [],
    this.currentTool,
    this.currentColor = const Color(0xFFFFEB3B),
    this.strokeWidth = 3.0,
    this.undoStack = const [],
    this.redoStack = const [],
    this.isModified = false,
    this.isProcessing = false,
    this.currentPageIndex = 0,
  });

  PdfEditorState copyWith({
    List<AnnotationModel>? annotations,
    AnnotationType? currentTool,
    bool clearTool = false,
    Color? currentColor,
    double? strokeWidth,
    List<List<AnnotationModel>>? undoStack,
    List<List<AnnotationModel>>? redoStack,
    bool? isModified,
    bool? isProcessing,
    int? currentPageIndex,
  }) {
    return PdfEditorState(
      annotations: annotations ?? this.annotations,
      currentTool: clearTool ? null : (currentTool ?? this.currentTool),
      currentColor: currentColor ?? this.currentColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      isModified: isModified ?? this.isModified,
      isProcessing: isProcessing ?? this.isProcessing,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
    );
  }

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  /// Annotations belonging to the currently visible page.
  List<AnnotationModel> get currentPageAnnotations =>
      annotations.where((a) => a.pageIndex == currentPageIndex).toList();
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class PdfEditorNotifier extends StateNotifier<PdfEditorState> {
  PdfEditorNotifier() : super(const PdfEditorState());

  // -- Tool selection --------------------------------------------------------

  void setTool(AnnotationType? tool) {
    if (tool == state.currentTool) {
      // Toggle off if same tool tapped again.
      state = state.copyWith(clearTool: true);
    } else {
      state = state.copyWith(currentTool: tool);
    }
  }

  // -- Color / stroke --------------------------------------------------------

  void setColor(Color color) {
    state = state.copyWith(currentColor: color);
  }

  void setStrokeWidth(double width) {
    state = state.copyWith(strokeWidth: width.clamp(1.0, 20.0));
  }

  // -- Page ------------------------------------------------------------------

  void setPage(int pageIndex) {
    state = state.copyWith(currentPageIndex: pageIndex);
  }

  // -- Annotation CRUD -------------------------------------------------------

  void addAnnotation(AnnotationModel annotation) {
    _pushUndo();
    state = state.copyWith(
      annotations: [...state.annotations, annotation],
      isModified: true,
      redoStack: const [], // clear redo on new action
    );
  }

  void removeAnnotation(String annotationId) {
    _pushUndo();
    state = state.copyWith(
      annotations:
          state.annotations.where((a) => a.id != annotationId).toList(),
      isModified: true,
      redoStack: const [],
    );
  }

  void updateAnnotation(AnnotationModel updated) {
    _pushUndo();
    state = state.copyWith(
      annotations: state.annotations
          .map((a) => a.id == updated.id ? updated : a)
          .toList(),
      isModified: true,
      redoStack: const [],
    );
  }

  // -- Undo / Redo -----------------------------------------------------------

  void undo() {
    if (!state.canUndo) return;
    final previousAnnotations = state.undoStack.last;
    final newUndoStack = List<List<AnnotationModel>>.from(state.undoStack)
      ..removeLast();
    state = state.copyWith(
      redoStack: [...state.redoStack, List.from(state.annotations)],
      annotations: previousAnnotations,
      undoStack: newUndoStack,
      isModified: true,
    );
  }

  void redo() {
    if (!state.canRedo) return;
    final nextAnnotations = state.redoStack.last;
    final newRedoStack = List<List<AnnotationModel>>.from(state.redoStack)
      ..removeLast();
    state = state.copyWith(
      undoStack: [...state.undoStack, List.from(state.annotations)],
      annotations: nextAnnotations,
      redoStack: newRedoStack,
      isModified: true,
    );
  }

  // -- Bulk operations -------------------------------------------------------

  void clearAll() {
    if (state.annotations.isEmpty) return;
    _pushUndo();
    state = state.copyWith(
      annotations: const [],
      isModified: true,
      redoStack: const [],
    );
  }

  // -- Processing flag -------------------------------------------------------

  void setProcessing(bool value) {
    state = state.copyWith(isProcessing: value);
  }

  // -- Save (called externally after actual save completes) ------------------

  void markSaved() {
    state = state.copyWith(isModified: false);
  }

  // -- Helpers ---------------------------------------------------------------

  void _pushUndo() {
    // Keep at most 30 undo levels.
    final stack = [...state.undoStack, List<AnnotationModel>.from(state.annotations)];
    if (stack.length > 30) stack.removeAt(0);
    state = state.copyWith(undoStack: stack);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final pdfEditorProvider =
    StateNotifierProvider.autoDispose<PdfEditorNotifier, PdfEditorState>(
  (ref) => PdfEditorNotifier(),
);
