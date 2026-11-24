import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/widgets/ad_banner_widget.dart';
import 'package:docuscan_pro/core/widgets/document_thumbnail.dart';
import 'package:docuscan_pro/core/widgets/empty_state_widget.dart';
import 'package:docuscan_pro/core/widgets/feature_card.dart';
import 'package:docuscan_pro/features/home/presentation/providers/home_provider.dart';
import 'package:docuscan_pro/features/file_management/presentation/screens/file_browser_screen.dart';
import 'package:docuscan_pro/features/settings/presentation/screens/settings_screen.dart';

// ---------------------------------------------------------------------------
// Bottom-nav tab index provider (local to home screen)
// ---------------------------------------------------------------------------

final _bottomNavIndexProvider = StateProvider<int>((ref) => 0);

// ---------------------------------------------------------------------------
// Home screen (shell with bottom navigation)
// ---------------------------------------------------------------------------

/// Main entry screen with a three-tab bottom navigation bar:
/// Home, Files, and Settings.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(_bottomNavIndexProvider);

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: const [
          _HomeTab(),
          FileBrowserScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) =>
            ref.read(_bottomNavIndexProvider.notifier).state = index,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_outlined),
            activeIcon: Icon(Icons.folder_rounded),
            label: 'Files',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: currentIndex == 0
          ? FloatingActionButton(
              onPressed: () => context.push('/scanner'),
              tooltip: AppStrings.scanDocument,
              child: const Icon(Icons.camera_alt_rounded),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Home tab content
// ---------------------------------------------------------------------------

class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quickActions = ref.watch(quickActionsProvider);
    final recentDocsAsync = ref.watch(recentDocumentsProvider);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // -- App bar --
          SliverAppBar(
            floating: true,
            snap: true,
            title: const Text(AppStrings.homeTitle),
            actions: [
              IconButton(
                icon: const Icon(Icons.search_rounded),
                tooltip: AppStrings.searchDocuments,
                onPressed: () => context.push('/files'),
              ),
            ],
          ),

          // -- Quick Actions heading --
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                AppStrings.quickActions,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),

          // -- 3x3 Feature grid --
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.9,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final action = quickActions[index];
                  return FeatureCard(
                    icon: action.icon,
                    label: action.label,
                    color: action.color,
                    badge: action.badge,
                    onTap: () => context.push(action.route),
                  );
                },
                childCount: quickActions.length,
              ),
            ),
          ),

          // -- Recent Documents heading --
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppStrings.recentDocuments,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/files'),
                    child: const Text('See All'),
                  ),
                ],
              ),
            ),
          ),

          // -- Recent Documents list --
          SliverToBoxAdapter(
            child: recentDocsAsync.when(
              data: (docs) {
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: EmptyStateWidget(
                      icon: Icons.document_scanner_outlined,
                      title: AppStrings.noRecentDocuments,
                      subtitle: AppStrings.startScanning,
                      iconSize: 56,
                    ),
                  );
                }

                return SizedBox(
                  height: 180,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      return _RecentDocumentCard(
                        title: doc.title,
                        date: doc.modifiedAt,
                        filePath: doc.filePath,
                        thumbnailPath: doc.thumbnailPath,
                        pageCount: doc.pageCount,
                        onTap: () => context.push(
                          '/pdf-viewer?path=${Uri.encodeComponent(doc.filePath)}',
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    AppStrings.errorGeneric,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
              ),
            ),
          ),

          // -- Ad banner --
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8),
              child: Center(child: AdBannerWidget()),
            ),
          ),

          // Bottom spacing so FAB does not obscure content
          const SliverToBoxAdapter(
            child: SizedBox(height: 80),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent document card
// ---------------------------------------------------------------------------

class _RecentDocumentCard extends StatelessWidget {
  final String title;
  final DateTime date;
  final String filePath;
  final String? thumbnailPath;
  final int pageCount;
  final VoidCallback? onTap;

  const _RecentDocumentCard({
    required this.title,
    required this.date,
    required this.filePath,
    this.thumbnailPath,
    required this.pageCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat.yMMMd().format(date);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            DocumentThumbnail(
              filePath: filePath,
              thumbnailPath: thumbnailPath,
              width: 130,
              height: 120,
              borderRadius: 12,
              pageCount: pageCount,
            ),
            const SizedBox(height: 8),

            // Title
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            // Date
            Text(
              dateStr,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
