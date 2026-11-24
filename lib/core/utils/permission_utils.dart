import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Helper class for requesting and managing app permissions.
class PermissionUtils {
  PermissionUtils._();

  /// Requests camera permission.
  ///
  /// Returns `true` if the permission is granted. If the user permanently
  /// denies the permission, a dialog is shown offering to open app settings.
  static Future<bool> requestCameraPermission(BuildContext context) async {
    return _requestPermission(
      context,
      permission: Permission.camera,
      title: 'Camera Permission Required',
      message:
          'DocuScan Pro needs camera access to scan documents. '
          'Please grant camera permission in your device settings.',
    );
  }

  /// Requests storage permission (photos / media library on iOS,
  /// external storage on Android).
  ///
  /// Returns `true` if the permission is granted.
  static Future<bool> requestStoragePermission(BuildContext context) async {
    return _requestPermission(
      context,
      permission: Permission.photos,
      title: 'Storage Permission Required',
      message:
          'DocuScan Pro needs access to your photos and files to import '
          'and save documents. Please grant storage permission in your '
          'device settings.',
    );
  }

  /// Shows an informational dialog when a permission has been denied.
  ///
  /// Provides an option to open the device's app settings so the user can
  /// manually grant the permission.
  static Future<void> showPermissionDeniedDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    if (!context.mounted) return;

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  static Future<bool> _requestPermission(
    BuildContext context, {
    required Permission permission,
    required String title,
    required String message,
  }) async {
    PermissionStatus status = await permission.status;

    if (status.isGranted) return true;

    // Request the permission.
    status = await permission.request();

    if (status.isGranted) return true;

    // If permanently denied, show a dialog directing to settings.
    if (status.isPermanentlyDenied && context.mounted) {
      await showPermissionDeniedDialog(
        context,
        title: title,
        message: message,
      );
    }

    return false;
  }
}
