import 'package:flutter/material.dart';

/// A widget that overlays its [child] with a semi-transparent loading
/// indicator when [isLoading] is `true`.
///
/// Optionally displays a [message] beneath the spinner.
///
/// ```dart
/// LoadingOverlay(
///   isLoading: _isSaving,
///   message: 'Saving document...',
///   child: MyContentWidget(),
/// )
/// ```
class LoadingOverlay extends StatelessWidget {
  /// Whether to show the loading overlay.
  final bool isLoading;

  /// Optional message displayed below the progress indicator.
  final String? message;

  /// The content behind the overlay.
  final Widget child;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    this.message,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: _buildIndicator(context),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildIndicator(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
