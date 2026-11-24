import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:docuscan_pro/features/home/presentation/screens/home_screen.dart';
import 'package:docuscan_pro/features/scanning/presentation/screens/scanner_screen.dart';
import 'package:docuscan_pro/features/scanning/presentation/screens/scan_review_screen.dart';
import 'package:docuscan_pro/features/pdf_viewer/presentation/screens/pdf_viewer_screen.dart';
import 'package:docuscan_pro/features/pdf_editor/presentation/screens/pdf_editor_screen.dart';
import 'package:docuscan_pro/features/pdf_editor/presentation/screens/annotation_screen.dart';
import 'package:docuscan_pro/features/pdf_operations/presentation/screens/merge_pdf_screen.dart';
import 'package:docuscan_pro/features/pdf_operations/presentation/screens/split_pdf_screen.dart';
import 'package:docuscan_pro/features/pdf_operations/presentation/screens/compress_pdf_screen.dart';
import 'package:docuscan_pro/features/pdf_operations/presentation/screens/password_protect_screen.dart';
import 'package:docuscan_pro/features/pdf_operations/presentation/screens/page_management_screen.dart';
import 'package:docuscan_pro/features/fill_sign/presentation/screens/fill_sign_screen.dart';
import 'package:docuscan_pro/features/fill_sign/presentation/screens/signature_pad_screen.dart';
import 'package:docuscan_pro/features/conversion/presentation/screens/conversion_screen.dart';
import 'package:docuscan_pro/features/file_management/presentation/screens/file_browser_screen.dart';
import 'package:docuscan_pro/features/ocr/presentation/screens/ocr_screen.dart';
import 'package:docuscan_pro/features/ocr/presentation/screens/table_extraction_screen.dart';
import 'package:docuscan_pro/features/qr_scanner/presentation/screens/qr_scanner_screen.dart';
import 'package:docuscan_pro/features/settings/presentation/screens/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/scanner',
        name: 'scanner',
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'] ?? 'document';
          return ScannerScreen(mode: ScanMode.fromString(mode));
        },
      ),
      GoRoute(
        path: '/scan-review',
        name: 'scan-review',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>;
          return ScanReviewScreen(
            imagePaths: data['imagePaths'] as List<String>,
            scanMode: data['scanMode'] as ScanMode,
          );
        },
      ),
      GoRoute(
        path: '/pdf-viewer',
        name: 'pdf-viewer',
        builder: (context, state) {
          final filePath = state.uri.queryParameters['path'] ?? '';
          return PdfViewerScreen(filePath: filePath);
        },
      ),
      GoRoute(
        path: '/pdf-editor',
        name: 'pdf-editor',
        builder: (context, state) {
          final filePath = state.uri.queryParameters['path'] ?? '';
          return PdfEditorScreen(filePath: filePath);
        },
      ),
      GoRoute(
        path: '/annotations',
        name: 'annotations',
        builder: (context, state) {
          final filePath = state.uri.queryParameters['path'] ?? '';
          return AnnotationScreen(filePath: filePath);
        },
      ),
      GoRoute(
        path: '/merge-pdf',
        name: 'merge-pdf',
        builder: (context, state) => const MergePdfScreen(),
      ),
      GoRoute(
        path: '/split-pdf',
        name: 'split-pdf',
        builder: (context, state) {
          final filePath = state.uri.queryParameters['path'] ?? '';
          return SplitPdfScreen(filePath: filePath);
        },
      ),
      GoRoute(
        path: '/compress-pdf',
        name: 'compress-pdf',
        builder: (context, state) {
          final filePath = state.uri.queryParameters['path'] ?? '';
          return CompressPdfScreen(filePath: filePath);
        },
      ),
      GoRoute(
        path: '/password-protect',
        name: 'password-protect',
        builder: (context, state) {
          final filePath = state.uri.queryParameters['path'] ?? '';
          return PasswordProtectScreen(filePath: filePath);
        },
      ),
      GoRoute(
        path: '/page-management',
        name: 'page-management',
        builder: (context, state) {
          final filePath = state.uri.queryParameters['path'] ?? '';
          return PageManagementScreen(filePath: filePath);
        },
      ),
      GoRoute(
        path: '/fill-sign',
        name: 'fill-sign',
        builder: (context, state) {
          final filePath = state.uri.queryParameters['path'] ?? '';
          return FillSignScreen(filePath: filePath);
        },
      ),
      GoRoute(
        path: '/signature-pad',
        name: 'signature-pad',
        builder: (context, state) => const SignaturePadScreen(),
      ),
      GoRoute(
        path: '/convert',
        name: 'convert',
        builder: (context, state) => const ConversionScreen(),
      ),
      GoRoute(
        path: '/files',
        name: 'files',
        builder: (context, state) => const FileBrowserScreen(),
      ),
      GoRoute(
        path: '/ocr',
        name: 'ocr',
        builder: (context, state) {
          final filePath = state.uri.queryParameters['path'] ?? '';
          return OcrScreen(filePath: filePath);
        },
      ),
      GoRoute(
        path: '/table-extraction',
        name: 'table-extraction',
        builder: (context, state) {
          final filePath = state.uri.queryParameters['path'] ?? '';
          return TableExtractionScreen(filePath: filePath);
        },
      ),
      GoRoute(
        path: '/qr-scanner',
        name: 'qr-scanner',
        builder: (context, state) => const QrScannerScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri.path}'),
      ),
    ),
  );
});
