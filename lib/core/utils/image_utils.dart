import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Utility class for image processing operations.
///
/// All methods accept raw image bytes and return processed image bytes.
/// Heavy computation is offloaded to isolates via [compute].
class ImageUtils {
  ImageUtils._();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Converts an image to grayscale.
  static Future<Uint8List> applyGrayscaleFilter(Uint8List imageBytes) async {
    return compute(_grayscaleIsolate, imageBytes);
  }

  /// Converts an image to black-and-white using a luminance [threshold].
  ///
  /// Pixels with luminance above the threshold become white; below become
  /// black. The default [threshold] of 128 works well for most documents.
  static Future<Uint8List> applyBWFilter(
    Uint8List imageBytes, {
    int threshold = 128,
  }) async {
    return compute(_bwIsolate, _BWParams(imageBytes, threshold));
  }

  /// Enhances an image by increasing contrast and sharpness.
  ///
  /// Ideal for scanned documents where text needs to be more legible.
  static Future<Uint8List> applyEnhancedFilter(Uint8List imageBytes) async {
    return compute(_enhancedIsolate, imageBytes);
  }

  /// Rotates an image by the given [degrees] (must be a multiple of 90).
  ///
  /// Supported values: 90, 180, 270 (or their negative equivalents).
  static Future<Uint8List> rotateImage(
    Uint8List imageBytes,
    int degrees,
  ) async {
    return compute(_rotateIsolate, _RotateParams(imageBytes, degrees));
  }

  /// Applies whiteboard-optimized processing: removes glare, boosts
  /// contrast aggressively, and normalizes the white background.
  ///
  /// This produces cleaner whiteboard captures compared to the generic
  /// enhanced filter, which is designed for printed documents.
  static Future<Uint8List> applyWhiteboardFilter(Uint8List imageBytes) async {
    return compute(_whiteboardIsolate, imageBytes);
  }

  /// Crops an image to the specified [rect] region.
  ///
  /// The [rect] coordinates are in pixel space of the source image.
  static Future<Uint8List> cropImage(
    Uint8List imageBytes,
    Rect rect,
  ) async {
    return compute(
      _cropIsolate,
      _CropParams(
        imageBytes,
        rect.left.toInt(),
        rect.top.toInt(),
        rect.width.toInt(),
        rect.height.toInt(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Isolate entry-point functions (must be top-level or static)
  // ---------------------------------------------------------------------------

  static Uint8List _grayscaleIsolate(Uint8List bytes) {
    final image = _decodeImage(bytes);
    final grayscale = img.grayscale(image);
    return _encodeImage(grayscale);
  }

  static Uint8List _bwIsolate(_BWParams params) {
    final image = _decodeImage(params.bytes);
    final grayscale = img.grayscale(image);

    // Apply binary threshold.
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final luminance = img.getLuminance(pixel);
        final value = luminance >= params.threshold ? 255 : 0;
        grayscale.setPixelRgb(x, y, value, value, value);
      }
    }

    return _encodeImage(grayscale);
  }

  static Uint8List _enhancedIsolate(Uint8List bytes) {
    var image = _decodeImage(bytes);

    // Increase contrast.
    image = img.adjustColor(image, contrast: 1.4);

    // Sharpen to improve text edges.
    image = img.convolution(image, filter: [
      0, -1, 0, //
      -1, 5, -1, //
      0, -1, 0, //
    ]);

    // Slightly increase brightness for washed-out scans.
    image = img.adjustColor(image, brightness: 1.05);

    return _encodeImage(image);
  }

  static Uint8List _whiteboardIsolate(Uint8List bytes) {
    var image = _decodeImage(bytes);

    // Step 1: Strong contrast boost to make marker text pop.
    image = img.adjustColor(image, contrast: 1.8);

    // Step 2: Normalize white background — push light grays to pure white
    // to remove glare and uneven lighting typical of whiteboard photos.
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        // If the pixel is "light enough" (near-white / glare), push to white.
        if (r > 180 && g > 180 && b > 180) {
          image.setPixelRgb(x, y, 255, 255, 255);
        } else {
          // Boost saturation of remaining (marker ink) pixels for clarity.
          final maxC = [r, g, b].reduce((a, b) => a > b ? a : b);
          final scale = maxC > 0 ? 255 / maxC : 1.0;
          image.setPixelRgb(
            x, y,
            (r * scale).clamp(0, 255).toInt(),
            (g * scale).clamp(0, 255).toInt(),
            (b * scale).clamp(0, 255).toInt(),
          );
        }
      }
    }

    // Step 3: Sharpen edges so text and diagrams are crisp.
    image = img.convolution(image, filter: [
      0, -1, 0,
      -1, 6, -1,
      0, -1, 0,
    ]);

    return _encodeImage(image);
  }

  static Uint8List _rotateIsolate(_RotateParams params) {
    final image = _decodeImage(params.bytes);
    final normalizedDegrees = ((params.degrees % 360) + 360) % 360;

    late img.Image rotated;
    switch (normalizedDegrees) {
      case 90:
        rotated = img.copyRotate(image, angle: 90);
        break;
      case 180:
        rotated = img.copyRotate(image, angle: 180);
        break;
      case 270:
        rotated = img.copyRotate(image, angle: 270);
        break;
      default:
        rotated = img.copyRotate(image, angle: normalizedDegrees.toDouble());
    }

    return _encodeImage(rotated);
  }

  static Uint8List _cropIsolate(_CropParams params) {
    final image = _decodeImage(params.bytes);

    // Clamp values to image bounds.
    final x = params.x.clamp(0, image.width - 1);
    final y = params.y.clamp(0, image.height - 1);
    final w = params.width.clamp(1, image.width - x);
    final h = params.height.clamp(1, image.height - y);

    final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);
    return _encodeImage(cropped);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static img.Image _decodeImage(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw ArgumentError('Unable to decode image from provided bytes.');
    }
    return decoded;
  }

  static Uint8List _encodeImage(img.Image image) {
    return Uint8List.fromList(img.encodePng(image));
  }
}

// ---------------------------------------------------------------------------
// Parameter classes for isolate communication
// ---------------------------------------------------------------------------

class _BWParams {
  final Uint8List bytes;
  final int threshold;
  const _BWParams(this.bytes, this.threshold);
}

class _RotateParams {
  final Uint8List bytes;
  final int degrees;
  const _RotateParams(this.bytes, this.degrees);
}

class _CropParams {
  final Uint8List bytes;
  final int x;
  final int y;
  final int width;
  final int height;
  const _CropParams(this.bytes, this.x, this.y, this.width, this.height);
}
