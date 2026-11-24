import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:docuscan_pro/core/constants/app_colors.dart';
import 'package:docuscan_pro/core/constants/app_strings.dart';
import 'package:docuscan_pro/core/services/ocr_service.dart';
import 'package:docuscan_pro/core/services/storage_service.dart';
import 'package:docuscan_pro/core/widgets/loading_overlay.dart';

class TableExtractionScreen extends StatefulWidget {
  final String filePath;
  const TableExtractionScreen({super.key, required this.filePath});

  @override
  State<TableExtractionScreen> createState() => _TableExtractionScreenState();
}

class _TableExtractionScreenState extends State<TableExtractionScreen> {
  TableExtractionResult? _result;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _extractTable();
  }

  Future<void> _extractTable() async {
    setState(() => _isProcessing = true);
    try {
      final result = await OcrService.extractTable(widget.filePath);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Table extraction failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _copyCsv() {
    if (_result == null || _result!.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _result!.csvContent));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Table copied as CSV')),
    );
  }

  Future<void> _exportCsv() async {
    if (_result == null || _result!.isEmpty) return;

    final path = await StorageService.getUniqueFilePath(
      StorageService.exportsDir,
      'table_${DateTime.now().millisecondsSinceEpoch}',
      'csv',
    );
    await File(path).writeAsString(_result!.csvContent);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: 'Extracted Table'),
    );
  }

  @override
  Widget build(BuildContext context) {

    return LoadingOverlay(
      isLoading: _isProcessing,
      message: 'Extracting table...',
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.extractTable),
          actions: [
            if (_result != null && !_result!.isEmpty)
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy CSV',
                onPressed: _copyCsv,
              ),
          ],
        ),
        body: _result == null
            ? const Center(child: CircularProgressIndicator())
            : _result!.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.table_chart_outlined,
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        const Text('No tables found'),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _extractTable,
                          child: const Text(AppStrings.retry),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Info
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: AppColors.secondary, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '${_result!.rowCount} rows x ${_result!.columnCount} columns',
                              style: const TextStyle(
                                color: AppColors.secondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Table
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Table(
                                border: TableBorder.all(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                defaultColumnWidth: const IntrinsicColumnWidth(),
                                children: _result!.rows.asMap().entries.map((entry) {
                                  final isHeader = entry.key == 0;
                                  return TableRow(
                                    decoration: BoxDecoration(
                                      color: isHeader
                                          ? AppColors.primary.withValues(alpha: 0.1)
                                          : entry.key.isOdd
                                              ? Colors.grey.shade50
                                              : null,
                                    ),
                                    children: entry.value.map((cell) {
                                      return Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Text(
                                          cell,
                                          style: TextStyle(
                                            fontWeight: isHeader
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            fontSize: 13,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Export buttons
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _copyCsv,
                                  icon: const Icon(Icons.copy),
                                  label: const Text('Copy CSV'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _exportCsv,
                                  icon: const Icon(Icons.share),
                                  label: const Text('Export CSV'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
