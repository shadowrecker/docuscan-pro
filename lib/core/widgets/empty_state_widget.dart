import 'package:flutter/material.dart';

/// A reusable empty-state placeholder with an icon, title, subtitle, and an
/// optional call-to-action button.
///
/// Useful for screens like an empty document list or search with no results.
class EmptyStateWidget extends StatelessWidget {
  /// Large icon displayed at the top.
  final IconData icon;

  /// Primary heading text.
  final String title;

  /// Descriptive secondary text.
  final String subtitle;

  /// Label for the optional action button. If `null`, the button is hidden.
  final String? actionLabel;

  /// Callback triggered when the action button is pressed.
  final VoidCallback? onAction;

  /// Size of the icon. Defaults to 80.
  final double iconSize;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.iconSize = 80,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: iconSize,
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
