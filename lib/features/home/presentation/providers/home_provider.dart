import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/models/document_model.dart';
import 'package:docuscan_pro/repositories/document_repository.dart';

// ---------------------------------------------------------------------------
// Repository provider
// ---------------------------------------------------------------------------

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepository();
});

// ---------------------------------------------------------------------------
// Recent documents
// ---------------------------------------------------------------------------

/// Fetches the 5 most recently modified documents.
final recentDocumentsProvider = FutureProvider<List<DocumentModel>>((ref) async {
  final repository = ref.watch(documentRepositoryProvider);
  return repository.getRecent(5);
});

// ---------------------------------------------------------------------------
// Quick action data model
// ---------------------------------------------------------------------------

/// Describes a single quick-action entry displayed on the home screen grid.
class QuickAction {
  final String label;
  final IconData icon;
  final Color color;
  final String route;
  final String? badge;

  const QuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.route,
    this.badge,
  });
}

// ---------------------------------------------------------------------------
// Quick actions provider
// ---------------------------------------------------------------------------

/// Returns the static list of quick-action items for the home screen grid.
final quickActionsProvider = Provider<List<QuickAction>>((ref) {
  return const [
    QuickAction(
      label: 'Scan Document',
      icon: Icons.document_scanner_outlined,
      color: AppColors.scanning,
      route: '/scanner?mode=document',
    ),
    QuickAction(
      label: 'Scan Whiteboard',
      icon: Icons.desktop_windows_outlined,
      color: Color(0xFF009688),
      route: '/scanner?mode=whiteboard',
    ),
    QuickAction(
      label: 'QR Scanner',
      icon: Icons.qr_code_scanner_rounded,
      color: AppColors.qrCode,
      route: '/qr-scanner',
    ),
    QuickAction(
      label: 'Edit PDF',
      icon: Icons.edit_document,
      color: AppColors.pdfEdit,
      route: '/pdf-editor',
    ),
    QuickAction(
      label: 'Merge PDFs',
      icon: Icons.merge_type_rounded,
      color: AppColors.merge,
      route: '/merge-pdf',
    ),
    QuickAction(
      label: 'Convert Files',
      icon: Icons.swap_horiz_rounded,
      color: AppColors.convert,
      route: '/convert',
    ),
    QuickAction(
      label: 'Fill & Sign',
      icon: Icons.draw_rounded,
      color: AppColors.sign,
      route: '/fill-sign',
    ),
    QuickAction(
      label: 'Compress PDF',
      icon: Icons.compress_rounded,
      color: AppColors.compress,
      route: '/compress-pdf',
    ),
    QuickAction(
      label: 'Password Protect',
      icon: Icons.lock_outline_rounded,
      color: AppColors.protect,
      route: '/password-protect',
    ),
  ];
});
