import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/ad_service.dart';
import 'package:docuscan_pro/core/services/pdf_service.dart';
import 'package:docuscan_pro/core/widgets/loading_overlay.dart';
import 'package:docuscan_pro/features/pdf_editor/presentation/providers/pdf_editor_provider.dart';
import 'package:docuscan_pro/models/annotation_model.dart';

/// Draws annotations over rendered page images. All geometry is stored
/// normalised (0–1) to the page as displayed, so it is independent of screen
/// size and maps directly onto the PDF when saved.
class AnnotationScreen extends ConsumerStatefulWidget {
  final String filePath;

  const AnnotationScreen({super.key, required this.filePath});

  @override
  ConsumerState<AnnotationScreen> createState() => _AnnotationScreenState();
}

class _AnnotationScreenState extends ConsumerState<AnnotationScreen> {
  List<String> _pageImages = [];
  final Map<int, Size> _pageSizes = {};
  String? _loadError;
  bool _isProcessing = false;

  // In-progress gesture, normalised.
  List<Offset> _currentStroke = [];
  Offset? _dragStart;
  Offset? _dragEnd;

  static const _markupTools = {
    AnnotationType.highlight,
    AnnotationType.underline,
    AnnotationType.strikethrough,
  };

  @override
  void initState() {
    super.initState();
    AdService.enterEditingMode();
    _renderPages();
  }

  @override
  void dispose() {
    AdService.exitEditingMode();
    super.dispose();
  }

  Future<void> _renderPages() async {
    try {
      // ~110 dpi is sharp on phones without a large memory cost per page.
      final images = await PdfService.pdfToImages(widget.filePath, format: 'jpg', dpi: 110);
      for (var i = 0; i < images.length; i++) {
        final decoded = await decodeImageFromList(await File(images[i]).readAsBytes());
        _pageSizes[i] = Size(decoded.width.toDouble(), decoded.height.toDouble());
        decoded.dispose();
      }
      if (mounted) setState(() => _pageImages = images);
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  Future<void> _saveAnnotations() async {
    final editorState = ref.read(pdfEditorProvider);
    if (!editorState.isModified || editorState.annotations.isEmpty) {
      context.pop();
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final result = await PdfService.applyAnnotations(
        widget.filePath,
        editorState.annotations.map((a) => a.toNative()).toList(),
      );
      ref.read(pdfEditorProvider.notifier).markSaved();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Annotations saved')),
      );
      context.pushReplacement('/pdf-viewer?path=${Uri.encodeComponent(result)}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Offset _normalise(Offset local, Size size) => Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      );

  void _onPanStart(DragStartDetails details, Size size) {
    final tool = ref.read(pdfEditorProvider).currentTool;
    final point = _normalise(details.localPosition, size);
    setState(() {
      if (tool == AnnotationType.freehand) {
        _currentStroke = [point];
      } else if (_markupTools.contains(tool)) {
        _dragStart = point;
        _dragEnd = point;
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final tool = ref.read(pdfEditorProvider).currentTool;
    final point = _normalise(details.localPosition, size);
    setState(() {
      if (tool == AnnotationType.freehand) {
        _currentStroke = [..._currentStroke, point];
      } else if (_markupTools.contains(tool)) {
        _dragEnd = point;
      }
    });
  }

  void _onPanEnd(DragEndDetails details, Size size) {
    final editorState = ref.read(pdfEditorProvider);
    final tool = editorState.currentTool;
    final notifier = ref.read(pdfEditorProvider.notifier);

    if (tool == AnnotationType.freehand && _currentStroke.length > 1) {
      notifier.addAnnotation(AnnotationModel.create(
        pageIndex: editorState.currentPageIndex,
        type: AnnotationType.freehand,
        color: editorState.currentColor.toARGB32(),
        points: _currentStroke.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        // The slider is in logical pixels of the on-screen page.
        strokeWidth: editorState.strokeWidth / size.width,
      ));
    } else if (_markupTools.contains(tool) && _dragStart != null && _dragEnd != null) {
      final rect = Rect.fromPoints(_dragStart!, _dragEnd!);
      // A sideways swipe over a line of text: give it at least one text-line of height.
      final minHeight = 14 / size.height;
      final height = rect.height < minHeight ? minHeight : rect.height;
      final top = rect.height < minHeight ? rect.center.dy - height / 2 : rect.top;
      if (rect.width * size.width > 8) {
        notifier.addAnnotation(AnnotationModel.create(
          pageIndex: editorState.currentPageIndex,
          type: tool!,
          color: editorState.currentColor.toARGB32(),
          rect: {'x': rect.left, 'y': top, 'width': rect.width, 'height': height},
        ));
      }
    }
    setState(() {
      _currentStroke = [];
      _dragStart = null;
      _dragEnd = null;
    });
  }

  void _onTapUp(TapUpDetails details, Size size) {
    final tool = ref.read(pdfEditorProvider).currentTool;
    if (tool == AnnotationType.textNote || tool == AnnotationType.stickyNote) {
      _showTextNoteDialog(_normalise(details.localPosition, size), tool!);
    }
  }

  void _showTextNoteDialog(Offset position, AnnotationType type) {
    final controller = TextEditingController();
    final editorState = ref.read(pdfEditorProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type == AnnotationType.stickyNote ? 'Sticky Note' : 'Text Note'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter note text...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref.read(pdfEditorProvider.notifier).addAnnotation(AnnotationModel.create(
                  pageIndex: editorState.currentPageIndex,
                  type: type,
                  color: editorState.currentColor.toARGB32(),
                  rect: {'x': position.dx, 'y': position.dy, 'width': 0, 'height': 0},
                  text: controller.text,
                ));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _showStickyNote(AnnotationModel note) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sticky Note'),
        content: Text(note.text ?? ''),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(pdfEditorProvider.notifier).removeAnnotation(note.id);
              Navigator.pop(ctx);
            },
            child: const Text(AppStrings.delete),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(pdfEditorProvider);

    return LoadingOverlay(
      isLoading: _isProcessing,
      message: 'Saving annotations...',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Annotate'),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: editorState.canUndo
                  ? () => ref.read(pdfEditorProvider.notifier).undo()
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: editorState.canRedo
                  ? () => ref.read(pdfEditorProvider.notifier).redo()
                  : null,
            ),
            TextButton(
              onPressed: _saveAnnotations,
              child: const Text(AppStrings.save),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildColorPicker(editorState),

            // Stroke width slider (for freehand)
            if (editorState.currentTool == AnnotationType.freehand)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.line_weight, size: 18),
                    Expanded(
                      child: Slider(
                        value: editorState.strokeWidth,
                        min: 1,
                        max: 20,
                        onChanged: (v) =>
                            ref.read(pdfEditorProvider.notifier).setStrokeWidth(v),
                      ),
                    ),
                    Text('${editorState.strokeWidth.round()}px'),
                  ],
                ),
              ),

            Expanded(child: _buildPageArea(editorState)),
            if (_pageImages.length > 1) _buildPageNavigator(editorState),
            _buildToolbar(editorState),
          ],
        ),
      ),
    );
  }

  Widget _buildPageArea(PdfEditorState editorState) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not open this PDF: $_loadError', textAlign: TextAlign.center),
        ),
      );
    }
    if (_pageImages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final pageIndex = editorState.currentPageIndex.clamp(0, _pageImages.length - 1);
    final pageSize = _pageSizes[pageIndex] ?? const Size(612, 792);
    final tool = editorState.currentTool;

    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.all(12),
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: pageSize.width / pageSize.height,
        child: LayoutBuilder(builder: (context, constraints) {
          final size = constraints.biggest;
          final pageAnnotations = editorState.currentPageAnnotations;
          return GestureDetector(
            onPanStart: tool != null ? (d) => _onPanStart(d, size) : null,
            onPanUpdate: tool != null ? (d) => _onPanUpdate(d, size) : null,
            onPanEnd: tool != null ? (d) => _onPanEnd(d, size) : null,
            onTapUp: tool != null ? (d) => _onTapUp(d, size) : null,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6),
                      ],
                    ),
                    child: Image.file(File(_pageImages[pageIndex]), fit: BoxFit.fill),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _AnnotationPainter(
                      annotations: pageAnnotations,
                      currentStroke: _currentStroke,
                      currentStrokeColor: editorState.currentColor,
                      currentStrokeWidth: editorState.strokeWidth / size.width,
                      dragRect: _dragStart != null && _dragEnd != null
                          ? Rect.fromPoints(_dragStart!, _dragEnd!)
                          : null,
                      dragTool: tool,
                    ),
                  ),
                ),
                // Sticky notes as tappable icons.
                ...pageAnnotations
                    .where((a) => a.type == AnnotationType.stickyNote)
                    .map((a) => Positioned(
                          left: (a.rect['x'] ?? 0) * size.width - 2,
                          top: (a.rect['y'] ?? 0) * size.height - 2,
                          child: GestureDetector(
                            onTap: () => _showStickyNote(a),
                            child: Icon(Icons.sticky_note_2, size: 26, color: Color(a.color)),
                          ),
                        )),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPageNavigator(PdfEditorState state) {
    final notifier = ref.read(pdfEditorProvider.notifier);
    final page = state.currentPageIndex;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: page > 0 ? () => notifier.setPage(page - 1) : null,
        ),
        Text('Page ${page + 1} of ${_pageImages.length}'),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: page < _pageImages.length - 1 ? () => notifier.setPage(page + 1) : null,
        ),
      ],
    );
  }

  Widget _buildColorPicker(PdfEditorState state) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: AppColors.annotationColors.map((color) {
          final isSelected = color.toARGB32() == state.currentColor.toARGB32();
          return GestureDetector(
            onTap: () => ref.read(pdfEditorProvider.notifier).setColor(color),
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primary : Colors.grey.shade300,
                  width: isSelected ? 3 : 1,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildToolbar(PdfEditorState state) {
    final tools = [
      (AnnotationType.highlight, Icons.highlight, AppStrings.highlight),
      (AnnotationType.underline, Icons.format_underline, AppStrings.underline),
      (AnnotationType.strikethrough, Icons.strikethrough_s, AppStrings.strikethrough),
      (AnnotationType.freehand, Icons.draw, AppStrings.freehand),
      (AnnotationType.textNote, Icons.text_fields, AppStrings.textNote),
      (AnnotationType.stickyNote, Icons.sticky_note_2, AppStrings.stickyNote),
    ];

    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: tools.map((tool) {
          final isSelected = state.currentTool == tool.$1;
          return GestureDetector(
            onTap: () => ref.read(pdfEditorProvider.notifier).setTool(tool.$1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    tool.$2,
                    size: 22,
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tool.$3,
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Paints saved annotations and the gesture in progress. Inputs are normalised;
/// they are scaled to the canvas here.
class _AnnotationPainter extends CustomPainter {
  final List<AnnotationModel> annotations;
  final List<Offset> currentStroke;
  final Color currentStrokeColor;
  final double currentStrokeWidth;
  final Rect? dragRect;
  final AnnotationType? dragTool;

  const _AnnotationPainter({
    required this.annotations,
    required this.currentStroke,
    required this.currentStrokeColor,
    required this.currentStrokeWidth,
    required this.dragRect,
    required this.dragTool,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Offset scale(Offset p) => Offset(p.dx * size.width, p.dy * size.height);

    for (final a in annotations) {
      final color = Color(a.color);
      switch (a.type) {
        case AnnotationType.highlight:
        case AnnotationType.underline:
        case AnnotationType.strikethrough:
          final r = Rect.fromLTWH(
            (a.rect['x'] ?? 0) * size.width,
            (a.rect['y'] ?? 0) * size.height,
            (a.rect['width'] ?? 0) * size.width,
            (a.rect['height'] ?? 0) * size.height,
          );
          _paintMarkup(canvas, a.type, r, color);
        case AnnotationType.freehand:
          if (a.points.length < 2) continue;
          _paintStroke(
            canvas,
            a.points.map((p) => scale(Offset(p['x'] ?? 0, p['y'] ?? 0))).toList(),
            color,
            a.strokeWidth * size.width,
          );
        case AnnotationType.textNote:
          final painter = TextPainter(
            text: TextSpan(text: a.text ?? '', style: TextStyle(color: color, fontSize: 12)),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: size.width);
          painter.paint(canvas, scale(Offset(a.rect['x'] ?? 0, a.rect['y'] ?? 0)));
        case AnnotationType.stickyNote:
          break; // Rendered as tappable widgets.
      }
    }

    if (currentStroke.length > 1) {
      _paintStroke(canvas, currentStroke.map(scale).toList(), currentStrokeColor,
          currentStrokeWidth * size.width);
    }
    if (dragRect != null && dragTool != null) {
      final r = Rect.fromLTRB(
        dragRect!.left * size.width,
        dragRect!.top * size.height,
        dragRect!.right * size.width,
        dragRect!.bottom * size.height,
      );
      _paintMarkup(canvas, dragTool!, r, currentStrokeColor);
    }
  }

  void _paintMarkup(Canvas canvas, AnnotationType type, Rect r, Color color) {
    if (type == AnnotationType.highlight) {
      canvas.drawRect(r, Paint()..color = color.withValues(alpha: 0.35));
      return;
    }
    final y = type == AnnotationType.underline ? r.bottom : r.center.dy;
    canvas.drawLine(
      Offset(r.left, y),
      Offset(r.right, y),
      Paint()
        ..color = color
        ..strokeWidth = (r.height * 0.08).clamp(1.0, 4.0),
    );
  }

  void _paintStroke(Canvas canvas, List<Offset> points, Color color, double width) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter old) =>
      annotations != old.annotations ||
      currentStroke != old.currentStroke ||
      dragRect != old.dragRect ||
      currentStrokeColor != old.currentStrokeColor;
}
