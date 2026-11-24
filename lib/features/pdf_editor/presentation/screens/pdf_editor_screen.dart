import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/ad_service.dart';
import 'package:docuscan_pro/core/services/pdf_service.dart';
import 'package:docuscan_pro/core/widgets/loading_overlay.dart';

class PdfEditorScreen extends ConsumerStatefulWidget {
  final String filePath;

  const PdfEditorScreen({super.key, required this.filePath});

  @override
  ConsumerState<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends ConsumerState<PdfEditorScreen> {
  bool _isProcessing = false;
  bool _isEditing = false;
  int _currentPage = 0;
  final Map<String, String> _textReplacements = {};
  final Map<String, Map<String, dynamic>> _textFormatting = {};
  String? _selectedText;
  final TextEditingController _editController = TextEditingController();
  double _fontSize = 14;
  bool _isBold = false;
  bool _isItalic = false;

  @override
  void initState() {
    super.initState();
    AdService.enterEditingMode();
  }

  @override
  void dispose() {
    AdService.exitEditingMode();
    _editController.dispose();
    super.dispose();
  }

  Future<void> _saveEdits() async {
    if (_textReplacements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No changes to save')),
      );
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final result = await PdfService.editPdfText(
        widget.filePath,
        _currentPage,
        _textReplacements,
        formatting: _textFormatting,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Changes saved successfully')),
      );
      context.pushReplacement('/pdf-viewer?path=${Uri.encodeComponent(result)}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _onTextSelected(String originalText) {
    setState(() {
      _selectedText = originalText;
      _editController.text = originalText;
      _isEditing = true;
    });
  }

  void _applyTextChange() {
    if (_selectedText != null) {
      if (_editController.text != _selectedText) {
        _textReplacements[_selectedText!] = _editController.text;
      }
      // Store formatting for this text replacement so the native layer
      // can preserve or apply font styling when writing back to the PDF.
      _textFormatting[_selectedText!] = {
        'fontSize': _fontSize,
        'bold': _isBold,
        'italic': _isItalic,
      };
    }
    setState(() {
      _isEditing = false;
      _selectedText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isProcessing,
      message: 'Saving changes...',
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.editPdf),
          actions: [
            if (_textReplacements.isNotEmpty)
              TextButton.icon(
                onPressed: _saveEdits,
                icon: const Icon(Icons.save),
                label: const Text(AppStrings.save),
              ),
          ],
        ),
        body: Column(
          children: [
            // Info banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: AppColors.primary.withValues(alpha: 0.1),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap on text in the PDF to select and edit it',
                      style: TextStyle(fontSize: 13, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),

            // PDF viewer with text selection
            Expanded(
              child: SfPdfViewer.file(
                File(widget.filePath),
                enableTextSelection: true,
                onTextSelectionChanged: (details) {
                  if (details.selectedText != null &&
                      details.selectedText!.isNotEmpty) {
                    _onTextSelected(details.selectedText!);
                  }
                },
                onPageChanged: (details) {
                  setState(() => _currentPage = details.newPageNumber - 1);
                },
              ),
            ),

            // Edit toolbar
            if (_isEditing) _buildEditPanel(),

            // Bottom toolbar
            _buildToolbar(),
          ],
        ),
      ),
    );
  }

  Widget _buildEditPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('Edit Text',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _isEditing = false),
                child: const Text(AppStrings.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _applyTextChange,
                child: const Text('Apply'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _editController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Edit selected text...',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 4,
        bottom: MediaQuery.of(context).padding.bottom + 4,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.text_decrease),
            tooltip: 'Decrease font size',
            onPressed: () => setState(() => _fontSize = (_fontSize - 1).clamp(8, 72)),
          ),
          Text('${_fontSize.round()}pt'),
          IconButton(
            icon: const Icon(Icons.text_increase),
            tooltip: 'Increase font size',
            onPressed: () => setState(() => _fontSize = (_fontSize + 1).clamp(8, 72)),
          ),
          const VerticalDivider(width: 24),
          IconButton(
            icon: Icon(
              Icons.format_bold,
              color: _isBold ? AppColors.primary : null,
            ),
            tooltip: 'Bold',
            onPressed: () => setState(() => _isBold = !_isBold),
          ),
          IconButton(
            icon: Icon(
              Icons.format_italic,
              color: _isItalic ? AppColors.primary : null,
            ),
            tooltip: 'Italic',
            onPressed: () => setState(() => _isItalic = !_isItalic),
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: _textReplacements.isNotEmpty
                ? () => setState(() => _textReplacements.remove(
                    _textReplacements.keys.last))
                : null,
          ),
        ],
      ),
    );
  }
}
