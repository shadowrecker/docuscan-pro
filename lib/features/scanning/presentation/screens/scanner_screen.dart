import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/services/storage_service.dart';
import 'package:docuscan_pro/core/utils/image_utils.dart';
import 'package:docuscan_pro/core/utils/permission_utils.dart';
import 'package:docuscan_pro/features/scanning/presentation/providers/scanner_provider.dart';
import 'package:docuscan_pro/features/settings/presentation/providers/settings_provider.dart';
// Prefixed: its ImageFormat clashes with camera's.
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart' as doc_scanner;

// ─────────────────────────────────────────────────────────────────────────────
// ScanMode Enum
// ─────────────────────────────────────────────────────────────────────────────

/// Scanning mode determines post-processing behavior.
enum ScanMode {
  document,
  whiteboard;

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case ScanMode.document:
        return 'Document';
      case ScanMode.whiteboard:
        return 'Whiteboard';
    }
  }

  /// Factory that converts a string value (e.g. from a route query parameter)
  /// into the corresponding [ScanMode].
  static ScanMode fromString(String value) {
    return ScanMode.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => ScanMode.document,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scanner Screen
// ─────────────────────────────────────────────────────────────────────────────

class ScannerScreen extends ConsumerStatefulWidget {
  final ScanMode mode;

  const ScannerScreen({super.key, this.mode = ScanMode.document});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  bool _isProcessing = false;
  FlashMode _flashMode = FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Set the initial scan mode from the route parameter.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scannerProvider.notifier).setMode(widget.mode);
    });
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle camera lifecycle with the app.
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
      setState(() => _isCameraInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  // ── Camera Initialisation ──────────────────────────────────────────────────

  Future<void> _initializeCamera() async {
    final hasPermission =
        await PermissionUtils.requestCameraPermission(context);
    if (!hasPermission) {
      if (mounted) context.pop();
      return;
    }

    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No cameras available')),
        );
        context.pop();
      }
      return;
    }

    // Prefer back camera.
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!.setFlashMode(_flashMode);
      if (mounted) setState(() => _isCameraInitialized = true);
    } on CameraException catch (e) {
      debugPrint('Camera initialisation error: ${e.description}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: ${e.description}')),
        );
      }
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _captureImage() async {
    // With auto edge detection on, the platform document scanner (ML Kit on
    // Android, VisionKit on iOS) does capture, edge detection, perspective
    // correction and multi-page scanning in one pass.
    if (ref.read(settingsProvider).autoEdgeDetection) {
      await _scanWithDocumentScanner();
      return;
    }

    if (_isCapturing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isCapturing = true;
      _isProcessing = true;
    });

    try {
      // Haptic feedback on capture.
      HapticFeedback.mediumImpact();

      final XFile file = await _cameraController!.takePicture();
      await _addCapturedPage(file.path, prefix: 'scan');
    } on CameraException catch (e) {
      debugPrint('Capture error: ${e.description}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: ${e.description}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _scanWithDocumentScanner() async {
    if (_isCapturing) return;
    setState(() {
      _isCapturing = true;
      _isProcessing = true;
    });

    // Release our camera so the platform scanner can open it.
    final controller = _cameraController;
    _cameraController = null;
    if (mounted) setState(() => _isCameraInitialized = false);
    await controller?.dispose();

    try {
      final result = await doc_scanner.FlutterDocScanner().getScannedDocumentAsImages(
        page: 20,
        imageFormat: doc_scanner.ImageFormat.jpeg,
        quality: 0.9,
      );
      for (final image in result?.images ?? const <String>[]) {
        // Android may return file:// URIs; iOS returns plain paths.
        final path = image.startsWith('file://') ? Uri.parse(image).toFilePath() : image;
        await _addCapturedPage(path, prefix: 'scan');
      }
    } on doc_scanner.DocScanException catch (e) {
      if (e.code != doc_scanner.DocScanException.codeCancelled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: ${e.message}')),
        );
      }
    } catch (e) {
      debugPrint('Document scanner error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _isProcessing = false;
        });
        await _initializeCamera();
      }
    }
  }

  /// Copies a captured page into app storage, applies mode-specific
  /// processing and adds it to the current scan.
  Future<void> _addCapturedPage(String sourcePath, {required String prefix}) async {
    // Copy to app storage so the camera-temp file can be cleaned up by the OS.
    final outputPath = await StorageService.getUniqueFilePath(
      StorageService.tempDir,
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}',
      'jpg',
    );
    await File(sourcePath).copy(outputPath);

    // Apply whiteboard-specific processing if in whiteboard mode.
    final scanMode = ref.read(scannerProvider).scanMode;
    if (scanMode == ScanMode.whiteboard) {
      final bytes = await File(outputPath).readAsBytes();
      final processed = await ImageUtils.applyWhiteboardFilter(bytes);
      await File(outputPath).writeAsBytes(processed);
    }

    ref.read(scannerProvider.notifier).addImage(outputPath);
  }

  Future<void> _importFromGallery() async {
    final hasPermission =
        await PermissionUtils.requestStoragePermission(context);
    if (!hasPermission) return;

    final picker = ImagePicker();
    final XFile? picked =
        await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _isProcessing = true);

    try {
      final outputPath = await StorageService.getUniqueFilePath(
        StorageService.tempDir,
        'import_${DateTime.now().millisecondsSinceEpoch}',
        'jpg',
      );
      await File(picked.path).copy(outputPath);
      ref.read(scannerProvider.notifier).addImage(outputPath);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;

    final FlashMode next;
    switch (_flashMode) {
      case FlashMode.off:
        next = FlashMode.auto;
        break;
      case FlashMode.auto:
        next = FlashMode.always;
        break;
      case FlashMode.always:
      case FlashMode.torch:
        next = FlashMode.off;
        break;
    }

    try {
      await _cameraController!.setFlashMode(next);
      setState(() => _flashMode = next);
    } on CameraException catch (e) {
      debugPrint('Flash toggle error: ${e.description}');
    }
  }

  void _onDone() {
    final scannerState = ref.read(scannerProvider);
    if (scannerState.capturedImages.isEmpty) return;

    context.pushNamed(
      'scan-review',
      extra: {
        'imagePaths': scannerState.capturedImages,
        'scanMode': scannerState.scanMode,
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scannerState = ref.watch(scannerProvider);
    final hasCaptures = scannerState.hasImages;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera preview
            _buildCameraPreview(),

            // Document guideline overlay
            _buildGuidelineOverlay(),

            // Processing indicator
            if (_isProcessing) _buildProcessingOverlay(),

            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(scannerState),
            ),

            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: hasCaptures
                  ? _buildMultiPageBottomBar(scannerState)
                  : _buildCaptureBottomBar(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Camera Preview ─────────────────────────────────────────────────────────

  Widget _buildCameraPreview() {
    if (!_isCameraInitialized || _cameraController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _cameraController!.value.previewSize?.height ?? 0,
          height: _cameraController!.value.previewSize?.width ?? 0,
          child: CameraPreview(_cameraController!),
        ),
      ),
    );
  }

  // ── Overlay Guidelines ─────────────────────────────────────────────────────

  Widget _buildGuidelineOverlay() {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 100),
        child: CustomPaint(
          painter: _DocumentGuidelinePainter(),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  // ── Processing Overlay ─────────────────────────────────────────────────────

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Processing...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top Bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar(ScannerState scannerState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              ref.read(scannerProvider.notifier).clear();
              context.pop();
            },
          ),

          const Spacer(),

          // Mode switcher
          _buildModeSwitcher(scannerState.scanMode),

          const Spacer(),

          // Page counter
          if (scannerState.hasImages)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${scannerState.pageCount} ${scannerState.pageCount == 1 ? 'page' : 'pages'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildModeSwitcher(ScanMode currentMode) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ScanMode.values.map((mode) {
          final isSelected = mode == currentMode;
          return GestureDetector(
            onTap: () => ref.read(scannerProvider.notifier).setMode(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                mode.label,
                style: TextStyle(
                  color: isSelected ? Colors.black87 : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Bottom Bars ────────────────────────────────────────────────────────────

  Widget _buildCaptureBottomBar() {
    return Container(
      padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Gallery import
          _buildCircleButton(
            icon: Icons.photo_library_outlined,
            onPressed: _importFromGallery,
            size: 48,
          ),

          // Capture button
          _buildCaptureButton(),

          // Flash toggle
          _buildCircleButton(
            icon: _flashIcon,
            onPressed: _toggleFlash,
            size: 48,
          ),
        ],
      ),
    );
  }

  Widget _buildMultiPageBottomBar(ScannerState scannerState) {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24, top: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thumbnail strip of captured pages
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: scannerState.capturedImages.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(scannerState.capturedImages[index]),
                    width: 42,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Action row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Add Page
              _buildActionButton(
                icon: Icons.add_a_photo_outlined,
                label: 'Add Page',
                onPressed: _captureImage,
              ),

              // Capture button (center)
              _buildCaptureButton(),

              // Done
              _buildActionButton(
                icon: Icons.check_circle_outline,
                label: 'Done',
                onPressed: _onDone,
                color: AppColors.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Reusable Button Widgets ────────────────────────────────────────────────

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _isCapturing ? null : _captureImage,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        padding: const EdgeInsets.all(4),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isCapturing ? Colors.grey : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
    double size = 48,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        style: IconButton.styleFrom(
          backgroundColor: Colors.white24,
          shape: const CircleBorder(),
        ),
        icon: Icon(icon, color: Colors.white, size: size * 0.5),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color color = Colors.white,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
      case FlashMode.torch:
        return Icons.flash_on;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Document Guideline Painter
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentGuidelinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final cornerLength = size.width * 0.08;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Top-left corner
    canvas.drawLine(rect.topLeft, Offset(rect.left + cornerLength, rect.top), paint);
    canvas.drawLine(rect.topLeft, Offset(rect.left, rect.top + cornerLength), paint);

    // Top-right corner
    canvas.drawLine(rect.topRight, Offset(rect.right - cornerLength, rect.top), paint);
    canvas.drawLine(rect.topRight, Offset(rect.right, rect.top + cornerLength), paint);

    // Bottom-left corner
    canvas.drawLine(rect.bottomLeft, Offset(rect.left + cornerLength, rect.bottom), paint);
    canvas.drawLine(rect.bottomLeft, Offset(rect.left, rect.bottom - cornerLength), paint);

    // Bottom-right corner
    canvas.drawLine(rect.bottomRight, Offset(rect.right - cornerLength, rect.bottom), paint);
    canvas.drawLine(rect.bottomRight, Offset(rect.right, rect.bottom - cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
