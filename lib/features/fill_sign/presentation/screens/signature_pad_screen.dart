import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/storage_service.dart';
import 'package:docuscan_pro/models/signature_model.dart';
import 'package:docuscan_pro/repositories/signature_repository.dart';

class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key});

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  Color _penColor = Colors.black;
  double _penWidth = 3.0;
  final TextEditingController _typeController = TextEditingController();
  String _selectedFont = 'Poppins';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _typeController.dispose();
    super.dispose();
  }

  void _clearSignature() {
    setState(() {
      _strokes.clear();
      _currentStroke.clear();
    });
  }

  Future<Uint8List?> _captureSignature() async {
    if (_tabController.index == 0) {
      // Draw mode
      if (_strokes.isEmpty) return null;
      return _renderDrawnSignature();
    } else {
      // Type mode
      if (_typeController.text.isEmpty) return null;
      return _renderTypedSignature();
    }
  }

  Future<Uint8List> _renderDrawnSignature() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = _penColor
      ..strokeWidth = _penWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(400, 150);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _renderTypedSignature() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final textPainter = TextPainter(
      text: TextSpan(
        text: _typeController.text,
        style: TextStyle(
          fontSize: 36,
          color: _penColor,
          fontFamily: _selectedFont,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(10, 50));

    final picture = recorder.endRecording();
    final width = (textPainter.width + 20).ceil().clamp(100, 600);
    final image = await picture.toImage(width, 150);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _done() async {
    final bytes = await _captureSignature();
    if (!mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create a signature first')),
      );
      return;
    }

    // Keep it for reuse (PRD F-01); failure to persist shouldn't block use.
    try {
      await _saveSignature(bytes);
    } catch (e) {
      debugPrint('Could not save signature for reuse: $e');
    }

    if (mounted) {
      context.pop(bytes);
    }
  }

  Future<void> _saveSignature(Uint8List bytes) async {

    final path = await StorageService.getUniqueFilePath(
      StorageService.signaturesDir,
      'signature_${DateTime.now().millisecondsSinceEpoch}',
      'png',
    );

    await File(path).writeAsBytes(bytes);

    final sig = SignatureModel.create(
      name: 'Signature ${DateTime.now().millisecondsSinceEpoch}',
      imagePath: path,
    );

    final repo = SignatureRepository();
    await repo.save(sig);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.addSignature),
        actions: [
          TextButton(
            onPressed: _done,
            child: const Text(AppStrings.done),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Draw'),
            Tab(text: 'Type'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Draw tab
          Column(
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _currentStroke = [details.localPosition];
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _currentStroke = [..._currentStroke, details.localPosition];
                      });
                    },
                    onPanEnd: (_) {
                      setState(() {
                        _strokes.add(List.from(_currentStroke));
                        _currentStroke = [];
                      });
                    },
                    child: CustomPaint(
                      painter: _SignaturePainter(
                        strokes: _strokes,
                        currentStroke: _currentStroke,
                        color: _penColor,
                        strokeWidth: _penWidth,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
              _buildDrawControls(),
            ],
          ),

          // Type tab
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _typeController,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(
                    fontSize: 32,
                    fontFamily: _selectedFont,
                    fontStyle: FontStyle.italic,
                    color: _penColor,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Type your name...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text('Font: '),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _selectedFont,
                      items: ['Poppins', 'Courier', 'serif', 'monospace']
                          .map((f) => DropdownMenuItem(
                                value: f,
                                child: Text(f, style: TextStyle(fontFamily: f)),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedFont = v!),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildColorPicker(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          _buildColorPicker(),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.line_weight, size: 18),
              Expanded(
                child: Slider(
                  value: _penWidth,
                  min: 1,
                  max: 10,
                  onChanged: (v) => setState(() => _penWidth = v),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _clearSignature,
                icon: const Icon(Icons.clear, size: 18),
                label: const Text(AppStrings.clearSignature),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker() {
    final colors = [Colors.black, AppColors.primary, Colors.red, Colors.green];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: colors.map((color) {
        final isSelected = color == _penColor;
        return GestureDetector(
          onTap: () => setState(() => _penColor = color),
          child: Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppColors.accent : Colors.grey.shade300,
                width: isSelected ? 3 : 1,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final Color color;
  final double strokeWidth;

  const _SignaturePainter({
    required this.strokes,
    required this.currentStroke,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in [...strokes, currentStroke]) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
