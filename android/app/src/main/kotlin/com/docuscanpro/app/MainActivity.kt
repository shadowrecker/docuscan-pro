package com.docuscanpro.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var pdfChannel: MethodChannel
    private lateinit var ocrChannel: MethodChannel
    private lateinit var conversionChannel: MethodChannel

    private val pdfHandler by lazy { PdfBoxHandler(applicationContext) }
    private val tesseractHandler by lazy { TesseractHandler(applicationContext) }
    private val cloudConversionHandler by lazy { CloudConversionHandler() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // PDF operations channel (Apache PDFBox)
        pdfChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.docuscanpro.app/pdf")
        pdfChannel.setMethodCallHandler { call, result ->
            val handler = pdfHandler
            when (call.method) {
                "mergePdfs" -> {
                    val pdfPaths = call.argument<List<String>>("pdfPaths")!!
                    val outputName = call.argument<String>("outputName")!!
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.mergePdfs(pdfPaths, outputName, outputDir, result)
                }
                "splitPdf" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val pageNumbers = call.argument<List<Int>>("pageNumbers")!!
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.splitPdf(pdfPath, pageNumbers, outputDir, result)
                }
                "compressPdf" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val quality = call.argument<Int>("quality")!!
                    val dpi = call.argument<Int>("dpi")!!
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.compressPdf(pdfPath, quality, dpi, outputDir, result)
                }
                "encryptPdf" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val password = call.argument<String>("password")!!
                    val allowPrinting = call.argument<Boolean>("allowPrinting") ?: true
                    val allowCopying = call.argument<Boolean>("allowCopying") ?: false
                    val allowEditing = call.argument<Boolean>("allowEditing") ?: false
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.encryptPdf(pdfPath, password, allowPrinting, allowCopying, allowEditing, outputDir, result)
                }
                "editPdfText" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val pageIndex = call.argument<Int>("pageIndex")!!
                    val replacements = call.argument<Map<String, String>>("replacements")!!
                    val formatting = call.argument<Map<String, Map<String, Any>>>("formatting") ?: emptyMap()
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.editPdfText(pdfPath, pageIndex, replacements, formatting, outputDir, result)
                }
                "reorderPages" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val newOrder = call.argument<List<Int>>("newOrder")!!
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.reorderPages(pdfPath, newOrder, outputDir, result)
                }
                "deletePages" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val pageIndices = call.argument<List<Int>>("pageIndices")!!
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.deletePages(pdfPath, pageIndices, outputDir, result)
                }
                "insertPages" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val insertAtIndex = call.argument<Int>("insertAtIndex")!!
                    val pagePaths = call.argument<List<String>>("pagePaths")!!
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.insertPages(pdfPath, insertAtIndex, pagePaths, outputDir, result)
                }
                "rotatePages" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val pageIndices = call.argument<List<Int>>("pageIndices")!!
                    val degrees = call.argument<Int>("degrees")!!
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.rotatePages(pdfPath, pageIndices, degrees, outputDir, result)
                }
                "addImageToPdf" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val pageIndex = call.argument<Int>("pageIndex")!!
                    val imageBytes = call.argument<ByteArray>("imageBytes")!!
                    val x = call.argument<Double>("x")!!.toFloat()
                    val y = call.argument<Double>("y")!!.toFloat()
                    val width = call.argument<Double>("width")!!.toFloat()
                    val height = call.argument<Double>("height")!!.toFloat()
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.addImageToPdf(pdfPath, pageIndex, imageBytes, x, y, width, height, outputDir, result)
                }
                "addTextToPdf" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val pageIndex = call.argument<Int>("pageIndex")!!
                    val text = call.argument<String>("text")!!
                    val x = call.argument<Double>("x")!!.toFloat()
                    val y = call.argument<Double>("y")!!.toFloat()
                    val fontSize = call.argument<Double>("fontSize")!!.toFloat()
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.addTextToPdf(pdfPath, pageIndex, text, x, y, fontSize, outputDir, result)
                }
                "pdfToImages" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val format = call.argument<String>("format") ?: "png"
                    val dpi = call.argument<Int>("dpi") ?: 300
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.pdfToImages(pdfPath, format, dpi, outputDir, result)
                }
                "getPdfInfo" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    handler.getPdfInfo(pdfPath, result)
                }
                "flattenAnnotations" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.flattenAnnotations(pdfPath, outputDir, result)
                }
                "applyAnnotations" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val annotations = call.argument<List<Map<String, Any?>>>("annotations")!!
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.applyAnnotations(pdfPath, annotations, outputDir, result)
                }
                "getFormFields" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    handler.getFormFields(pdfPath, result)
                }
                "fillFormFields" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val fieldValues = call.argument<Map<String, String>>("fieldValues")!!
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.fillFormFields(pdfPath, fieldValues, outputDir, result)
                }
                "addOcrTextLayer" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    val pages = call.argument<List<Map<String, Any?>>>("pages")!!
                    val outputDir = call.argument<String>("outputDir")!!
                    handler.addOcrTextLayer(pdfPath, pages, outputDir, result)
                }
                "extractPdfContent" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    handler.extractPdfContent(pdfPath, result)
                }
                else -> result.notImplemented()
            }
        }

        // OCR channel (Tesseract)
        ocrChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.docuscanpro.app/ocr")
        ocrChannel.setMethodCallHandler { call, result ->
            val handler = tesseractHandler
            when (call.method) {
                "recognizeText" -> {
                    val imagePath = call.argument<String>("imagePath")!!
                    val languageCode = call.argument<String>("languageCode")!!
                    handler.recognizeText(imagePath, languageCode, result)
                }
                "downloadLanguagePack" -> {
                    val languageCode = call.argument<String>("languageCode")!!
                    handler.downloadLanguagePack(languageCode, result)
                }
                "getAvailableLanguages" -> {
                    handler.getAvailableLanguages(result)
                }
                else -> result.notImplemented()
            }
        }

        // Conversion channel
        conversionChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.docuscanpro.app/conversion")
        conversionChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "extractPdfContent" -> {
                    val pdfPath = call.argument<String>("pdfPath")!!
                    pdfHandler.extractPdfContent(pdfPath, result)
                }
                "cloudConvert" -> {
                    val fileContent = call.argument<String>("fileContent")!!
                    val sourceFormat = call.argument<String>("sourceFormat")!!
                    val targetFormat = call.argument<String>("targetFormat")!!
                    val baseUrl = call.argument<String>("baseUrl")!!
                    val apiKey = call.argument<String>("apiKey")
                    cloudConversionHandler.convert(fileContent, sourceFormat, targetFormat, baseUrl, apiKey, result)
                }
                else -> result.notImplemented()
            }
        }
    }
}
