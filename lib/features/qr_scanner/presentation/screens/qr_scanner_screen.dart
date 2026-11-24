import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  MobileScannerController? _controller;
  String? _scannedValue;
  bool _isFlashOn = false;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null) return;

    _handleResult(value);
  }

  void _handleResult(String value) {
    setState(() {
      _scannedValue = value;
      _hasScanned = true;
    });

    HapticFeedback.mediumImpact();
    _controller?.stop();

    _showResultSheet();
  }

  /// Decodes a QR/barcode from an image picked from the gallery (PRD S-03).
  Future<void> _scanFromGallery() async {
    if (_hasScanned) return;

    final XFile? image;
    try {
      image = await ImagePicker().pickImage(source: ImageSource.gallery);
    } catch (e) {
      _showMessage('Could not open gallery: $e');
      return;
    }
    if (image == null || !mounted) return;

    try {
      final capture = await _controller?.analyzeImage(image.path);
      final value = capture?.barcodes
          .map((b) => b.rawValue)
          .whereType<String>()
          .firstOrNull;
      if (!mounted) return;
      if (value == null) {
        _showMessage('No QR code found in that image');
        return;
      }
      _handleResult(value);
    } on UnsupportedError {
      _showMessage('Scanning images is not supported on this device');
    } catch (e) {
      _showMessage('Could not read the image: $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showResultSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(ctx).padding.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Icon(Icons.qr_code_2, size: 48, color: AppColors.primary),
            const SizedBox(height: 16),
            const Text(
              AppStrings.qrResult,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _scannedValue ?? '',
                style: const TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: _scannedValue ?? ''),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text(AppStrings.copyResult),
                  ),
                ),
                if (_isUrl(_scannedValue)) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final uri = Uri.tryParse(_scannedValue!);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text(AppStrings.openUrl),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _resetScanner();
                },
                child: const Text('Scan Another'),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      if (mounted && _hasScanned) {
        // If sheet dismissed without action, allow re-scanning
        _resetScanner();
      }
    });
  }

  void _resetScanner() {
    setState(() {
      _hasScanned = false;
      _scannedValue = null;
    });
    _controller?.start();
  }

  bool _isUrl(String? value) {
    if (value == null) return false;
    return value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('www.');
  }

  void _toggleFlash() async {
    await _controller?.toggleTorch();
    setState(() => _isFlashOn = !_isFlashOn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera
          if (_controller != null)
            MobileScanner(
              controller: _controller!,
              onDetect: _onDetect,
            ),

          // Overlay
          _buildScanOverlay(),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => context.pop(),
                    ),
                    const Expanded(
                      child: Text(
                        AppStrings.qrScanner,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.photo_library_outlined,
                          color: Colors.white),
                      tooltip: 'Scan from image',
                      onPressed: _scanFromGallery,
                    ),
                    IconButton(
                      icon: Icon(
                        _isFlashOn ? Icons.flash_on : Icons.flash_off,
                        color: Colors.white,
                      ),
                      onPressed: _toggleFlash,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Instruction + import from gallery
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppStrings.pointCamera,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _scanFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Scan from image'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScanOverlayPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scanAreaSize = size.width * 0.7;
    final left = (size.width - scanAreaSize) / 2;
    final top = (size.height - scanAreaSize) / 2;
    final scanRect = Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize);

    // Dark overlay
    final overlayPaint = Paint()..color = Colors.black54;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, scanRect.top), overlayPaint);
    canvas.drawRect(
      Rect.fromLTWH(0, scanRect.bottom, size.width, size.height - scanRect.bottom),
      overlayPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, scanRect.top, scanRect.left, scanAreaSize),
      overlayPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(scanRect.right, scanRect.top, size.width - scanRect.right, scanAreaSize),
      overlayPaint,
    );

    // Corner brackets
    final cornerPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const cornerLen = 30.0;

    // Top-left
    canvas.drawLine(scanRect.topLeft, Offset(scanRect.left + cornerLen, scanRect.top), cornerPaint);
    canvas.drawLine(scanRect.topLeft, Offset(scanRect.left, scanRect.top + cornerLen), cornerPaint);

    // Top-right
    canvas.drawLine(scanRect.topRight, Offset(scanRect.right - cornerLen, scanRect.top), cornerPaint);
    canvas.drawLine(scanRect.topRight, Offset(scanRect.right, scanRect.top + cornerLen), cornerPaint);

    // Bottom-left
    canvas.drawLine(scanRect.bottomLeft, Offset(scanRect.left + cornerLen, scanRect.bottom), cornerPaint);
    canvas.drawLine(scanRect.bottomLeft, Offset(scanRect.left, scanRect.bottom - cornerLen), cornerPaint);

    // Bottom-right
    canvas.drawLine(scanRect.bottomRight, Offset(scanRect.right - cornerLen, scanRect.bottom), cornerPaint);
    canvas.drawLine(scanRect.bottomRight, Offset(scanRect.right, scanRect.bottom - cornerLen), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
