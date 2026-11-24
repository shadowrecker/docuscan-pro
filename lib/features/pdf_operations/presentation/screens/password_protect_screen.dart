import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/pdf_service.dart';
import 'package:docuscan_pro/core/widgets/loading_overlay.dart';

class PasswordProtectScreen extends StatefulWidget {
  final String filePath;
  const PasswordProtectScreen({super.key, required this.filePath});

  @override
  State<PasswordProtectScreen> createState() => _PasswordProtectScreenState();
}

class _PasswordProtectScreenState extends State<PasswordProtectScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _allowPrinting = true;
  bool _allowCopying = false;
  bool _allowEditing = false;
  bool _isProcessing = false;
  String? _protectedPath;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String get _passwordStrength {
    final pwd = _passwordController.text;
    if (pwd.length < 4) return '';
    if (pwd.length < 6) return 'Weak';
    if (pwd.length < 8) return 'Medium';
    final hasUpper = pwd.contains(RegExp(r'[A-Z]'));
    final hasLower = pwd.contains(RegExp(r'[a-z]'));
    final hasDigit = pwd.contains(RegExp(r'[0-9]'));
    final hasSpecial = pwd.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));
    final variety = [hasUpper, hasLower, hasDigit, hasSpecial].where((b) => b).length;
    if (variety >= 3 && pwd.length >= 8) return 'Strong';
    return 'Medium';
  }

  Color get _strengthColor {
    switch (_passwordStrength) {
      case 'Weak':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      case 'Strong':
        return AppColors.secondary;
      default:
        return Colors.transparent;
    }
  }

  String? get _validationError {
    if (_passwordController.text.length < 4) return 'Minimum 4 characters';
    if (_passwordController.text != _confirmController.text) {
      return AppStrings.passwordMismatch;
    }
    return null;
  }

  Future<void> _protect() async {
    final error = _validationError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final result = await PdfService.passwordProtectPdf(
        widget.filePath,
        password: _passwordController.text,
        allowPrinting: _allowPrinting,
        allowCopying: _allowCopying,
        allowEditing: _allowEditing,
      );

      if (!mounted) return;
      setState(() => _protectedPath = result);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF protected successfully')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Protection failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LoadingOverlay(
      isLoading: _isProcessing,
      message: 'Encrypting PDF...',
      child: Scaffold(
        appBar: AppBar(title: const Text(AppStrings.passwordProtect)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Password field
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: AppStrings.setPassword,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),

            // Password strength indicator
            if (_passwordController.text.length >= 4)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: _passwordStrength == 'Weak'
                            ? 0.33
                            : _passwordStrength == 'Medium'
                                ? 0.66
                                : 1.0,
                        color: _strengthColor,
                        backgroundColor: Colors.grey.shade200,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _passwordStrength,
                      style: TextStyle(
                        color: _strengthColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Confirm password field
            TextField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: AppStrings.confirmPassword,
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
                errorText: _confirmController.text.isNotEmpty &&
                        _passwordController.text != _confirmController.text
                    ? AppStrings.passwordMismatch
                    : null,
              ),
            ),
            const SizedBox(height: 24),

            // Permissions section
            Text(
              AppStrings.permissions,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text(AppStrings.allowPrinting),
              value: _allowPrinting,
              onChanged: (v) => setState(() => _allowPrinting = v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text(AppStrings.allowCopying),
              value: _allowCopying,
              onChanged: (v) => setState(() => _allowCopying = v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text(AppStrings.allowEditing),
              value: _allowEditing,
              onChanged: (v) => setState(() => _allowEditing = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),

            // Action buttons
            if (_protectedPath != null) ...[
              Card(
                color: AppColors.secondary.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppColors.secondary, size: 36),
                      const SizedBox(height: 8),
                      const Text('PDF Protected!',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => SharePlus.instance.share(
                                ShareParams(files: [XFile(_protectedPath!)]),
                              ),
                              icon: const Icon(Icons.share),
                              label: const Text(AppStrings.share),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => context.pushReplacement(
                                '/pdf-viewer?path=${Uri.encodeComponent(_protectedPath!)}',
                              ),
                              icon: const Icon(Icons.visibility),
                              label: const Text('View'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ] else
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _passwordController.text.length >= 4 &&
                          _passwordController.text == _confirmController.text
                      ? _protect
                      : null,
                  icon: const Icon(Icons.lock),
                  label: const Text('Protect PDF'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
