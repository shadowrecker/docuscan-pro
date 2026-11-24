import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart' hide PdfFormField;

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/ad_service.dart';
import 'package:docuscan_pro/core/services/pdf_service.dart';
import 'package:docuscan_pro/core/widgets/loading_overlay.dart';

class FillSignScreen extends ConsumerStatefulWidget {
  final String filePath;
  const FillSignScreen({super.key, required this.filePath});

  @override
  ConsumerState<FillSignScreen> createState() => _FillSignScreenState();
}

class _FillSignScreenState extends ConsumerState<FillSignScreen> {
  bool _isProcessing = false;
  int _currentPage = 0;
  final List<_PlacedElement> _placedElements = [];
  late final PdfViewerController _pdfController;
  List<PdfFormField> _formFields = [];
  final Map<String, TextEditingController> _formControllers = {};

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    AdService.enterEditingMode();
    _detectFormFields();
  }

  @override
  void dispose() {
    AdService.exitEditingMode();
    _pdfController.dispose();
    for (final c in _formControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _detectFormFields() async {
    try {
      final fields = await PdfService.getFormFields(widget.filePath);
      setState(() {
        _formFields = fields;
        for (final field in fields) {
          _formControllers[field.name] = TextEditingController(text: field.value);
        }
      });
    } catch (_) {
      // PDF has no form fields — the user can still use manual placement
    }
  }

  Future<void> _fillFormFields() async {
    if (_formControllers.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final fieldValues = <String, String>{};
      for (final entry in _formControllers.entries) {
        fieldValues[entry.key] = entry.value.text;
      }
      final result = await PdfService.fillFormFields(
        widget.filePath,
        fieldValues,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Form filled successfully')),
        );
        context.pushReplacement(
          '/pdf-viewer?path=${Uri.encodeComponent(result)}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fill form: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _addSignature() async {
    final result = await context.push<Uint8List>('/signature-pad');
    if (result == null || !mounted) return;

    setState(() {
      _placedElements.add(_PlacedElement(
        type: _FillSignTool.signature,
        position: const Offset(100, 300),
        imageBytes: result,
      ));
    });
  }

  void _addText() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.addText),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter text...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  _placedElements.add(_PlacedElement(
                    type: _FillSignTool.text,
                    position: const Offset(100, 300),
                    text: controller.text,
                  ));
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _addCheckmark() {
    setState(() {
      _placedElements.add(const _PlacedElement(
        type: _FillSignTool.checkmark,
        position: Offset(100, 300),
      ));
    });
  }

  void _addDate() {
    setState(() {
      _placedElements.add(_PlacedElement(
        type: _FillSignTool.date,
        position: const Offset(100, 300),
        text: _formatDate(DateTime.now()),
      ));
    });
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  Future<void> _saveFillSign() async {
    if (_placedElements.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      String currentPath = widget.filePath;

      for (final element in _placedElements) {
        if (element.type == _FillSignTool.signature && element.imageBytes != null) {
          currentPath = await PdfService.addSignatureToPdf(
            currentPath,
            _currentPage,
            element.imageBytes!,
            element.position.dx,
            element.position.dy,
            150,
            50,
          );
        } else if (element.text != null) {
          currentPath = await PdfService.addTextToPdf(
            currentPath,
            _currentPage,
            element.text!,
            element.position.dx,
            element.position.dy,
            14,
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document saved')),
      );
      context.pushReplacement(
        '/pdf-viewer?path=${Uri.encodeComponent(currentPath)}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isProcessing,
      message: 'Saving...',
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.fillAndSign),
          actions: [
            if (_placedElements.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.undo),
                onPressed: () => setState(_placedElements.removeLast),
              ),
            if (_formFields.isNotEmpty)
              TextButton(
                onPressed: _fillFormFields,
                child: const Text('Fill Form'),
              ),
            TextButton(
              onPressed: (_placedElements.isNotEmpty || _formControllers.isNotEmpty) ? _saveFillSign : null,
              child: const Text(AppStrings.save),
            ),
          ],
        ),
        body: Column(
          children: [
            // Form fields panel (shown when interactive form detected)
            if (_formFields.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.primary.withValues(alpha: 0.05),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.edit_note, size: 18, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          '${_formFields.length} form field(s) detected',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: _formFields.length > 2 ? 120 : 60,
                      child: ListView.separated(
                        itemCount: _formFields.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final field = _formFields[index];
                          return SizedBox(
                            height: 40,
                            child: TextField(
                              controller: _formControllers[field.name],
                              decoration: InputDecoration(
                                labelText: field.name,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8,
                                ),
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

            // PDF with placed elements overlay
            Expanded(
              child: Stack(
                children: [
                  SfPdfViewer.file(
                    File(widget.filePath),
                    controller: _pdfController,
                    enableDoubleTapZooming: true,
                    onPageChanged: (details) {
                      setState(() => _currentPage = details.newPageNumber - 1);
                    },
                  ),

                  // Placed elements
                  ..._placedElements.asMap().entries.map((entry) {
                    final index = entry.key;
                    final element = entry.value;

                    return Positioned(
                      left: element.position.dx,
                      top: element.position.dy,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            _placedElements[index] = element.copyWith(
                              position: element.position + details.delta,
                            );
                          });
                        },
                        onLongPress: () {
                          setState(() => _placedElements.removeAt(index));
                        },
                        child: _buildElementWidget(element),
                      ),
                    );
                  }),
                ],
              ),
            ),

            // Toolbar
            _buildToolbar(),
          ],
        ),
      ),
    );
  }

  Widget _buildElementWidget(_PlacedElement element) {
    switch (element.type) {
      case _FillSignTool.signature:
        if (element.imageBytes != null) {
          return Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Image.memory(
              element.imageBytes!,
              width: 150,
              height: 50,
              fit: BoxFit.contain,
            ),
          );
        }
        return const SizedBox();
      case _FillSignTool.text:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary, width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            element.text ?? '',
            style: const TextStyle(fontSize: 14),
          ),
        );
      case _FillSignTool.checkmark:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary, width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: const Icon(Icons.check, size: 18, color: AppColors.primary),
        );
      case _FillSignTool.date:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary, width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            element.text ?? '',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        );
    }
  }

  Widget _buildToolbar() {
    final tools = [
      (_FillSignTool.signature, Icons.draw, AppStrings.addSignature),
      (_FillSignTool.text, Icons.text_fields, AppStrings.addText),
      (_FillSignTool.checkmark, Icons.check_box, AppStrings.addCheckmark),
      (_FillSignTool.date, Icons.calendar_today, AppStrings.addDate),
    ];

    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: tools.map((tool) {
          return GestureDetector(
            onTap: () {
              switch (tool.$1) {
                case _FillSignTool.signature:
                  _addSignature();
                case _FillSignTool.text:
                  _addText();
                case _FillSignTool.checkmark:
                  _addCheckmark();
                case _FillSignTool.date:
                  _addDate();
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(tool.$2, size: 24, color: AppColors.primary),
                const SizedBox(height: 4),
                Text(tool.$3, style: const TextStyle(fontSize: 11)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

enum _FillSignTool { signature, text, checkmark, date }

class _PlacedElement {
  final _FillSignTool type;
  final Offset position;
  final Uint8List? imageBytes;
  final String? text;

  const _PlacedElement({
    required this.type,
    required this.position,
    this.imageBytes,
    this.text,
  });

  _PlacedElement copyWith({Offset? position}) {
    return _PlacedElement(
      type: type,
      position: position ?? this.position,
      imageBytes: imageBytes,
      text: text,
    );
  }
}
