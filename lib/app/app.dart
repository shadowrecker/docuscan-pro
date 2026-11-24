import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:docuscan_pro/app/router.dart';
import 'package:docuscan_pro/core/theme/app_theme.dart';
import 'package:docuscan_pro/features/settings/presentation/providers/settings_provider.dart';

class DocuScanProApp extends ConsumerWidget {
  const DocuScanProApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(settingsProvider).themeMode;

    return MaterialApp.router(
      title: 'DocuScan Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
