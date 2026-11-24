import 'package:flutter/material.dart';

/// A card widget designed for the home-screen feature grid.
///
/// Displays an [icon] inside a coloured circle, a text [label], and an
/// optional [badge] (e.g., "NEW", "PRO") in the top-right corner.
class FeatureCard extends StatelessWidget {
  /// Icon displayed in the centre of the coloured circle.
  final IconData icon;

  /// Label text shown beneath the icon.
  final String label;

  /// Background tint colour for the icon circle.
  final Color color;

  /// Called when the card is tapped.
  final VoidCallback? onTap;

  /// Optional badge text displayed in the top-right corner of the card.
  /// Pass `null` or an empty string to hide the badge.
  final String? badge;

  const FeatureCard({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBadge = badge != null && badge!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildIconCircle(theme),
                    const SizedBox(height: 8),
                    // Flexible so two-line labels (or large system text sizes)
                    // ellipsize instead of overflowing the card.
                    Flexible(
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasBadge)
                Positioned(top: 6, right: 6, child: _buildBadge(theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconCircle(ThemeData theme) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        badge!,
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
