package com.docuscanpro.app

import android.content.Context
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File

/**
 * Handles Tesseract 5 OCR operations for extended language support
 * (Tesseract4Android). Tesseract covers Cyrillic, Arabic, Thai, Hebrew,
 * Bengali, and 50+ more scripts that ML Kit doesn't, fully offline once the
 * language pack has been downloaded.
 */
class TesseractHandler(private val context: Context) {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Tesseract expects the *parent* of the "tessdata" directory as its data path.
    private val dataPath: File
        get() = context.filesDir

    private val tessDataDir: File
        get() = File(dataPath, "tessdata")

    init {
        tessDataDir.mkdirs()
    }

    /**
     * Run OCR on an image using Tesseract with the specified language
     * (Tesseract 3-letter code, e.g. "rus", "ara").
     */
    fun recognizeText(
        imagePath: String,
        languageCode: String,
        result: MethodChannel.Result
    ) {
        scope.launch {
            val langFile = File(tessDataDir, "${languageCode}.traineddata")
            if (!langFile.exists()) {
                withContext(Dispatchers.Main) {
                    result.error(
                        "LANGUAGE_NOT_DOWNLOADED",
                        "Language pack '$languageCode' is not downloaded",
                        null
                    )
                }
                return@launch
            }

            val tess = TessBaseAPI()
            try {
                if (!tess.init(dataPath.absolutePath, languageCode, TessBaseAPI.OEM_LSTM_ONLY)) {
                    throw IllegalStateException("Could not load language pack '$languageCode'")
                }
                tess.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
                tess.setImage(File(imagePath))
                val text = tess.getUTF8Text() ?: ""

                val blocks = mutableListOf<Map<String, Any>>()
                val iterator = tess.resultIterator
                if (iterator != null) {
                    val level = TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE
                    iterator.begin()
                    do {
                        val lineText = iterator.getUTF8Text(level)?.trim()
                        if (!lineText.isNullOrEmpty()) {
                            val rect = iterator.getBoundingRect(level)
                            blocks.add(
                                mapOf(
                                    "text" to lineText,
                                    "confidence" to iterator.confidence(level).toDouble(),
                                    "bounds" to mapOf(
                                        "left" to rect.left,
                                        "top" to rect.top,
                                        "width" to rect.width(),
                                        "height" to rect.height()
                                    )
                                )
                            )
                        }
                    } while (iterator.next(level))
                    iterator.delete()
                }

                withContext(Dispatchers.Main) {
                    result.success(mapOf("text" to text, "blocks" to blocks))
                }
            } catch (e: Throwable) {
                withContext(Dispatchers.Main) {
                    result.error("OCR_ERROR", e.message ?: e.javaClass.simpleName, null)
                }
            } finally {
                tess.recycle()
            }
        }
    }

    /**
     * Download a Tesseract language pack from the tessdata_fast repository.
     * Written to a temporary file and renamed on success, so an interrupted
     * download can never leave a truncated pack that looks installed.
     */
    fun downloadLanguagePack(
        languageCode: String,
        result: MethodChannel.Result
    ) {
        scope.launch {
            try {
                require(languageCode.matches(Regex("^[a-z_]{3,12}$"))) { "Invalid language code" }
                val langFile = File(tessDataDir, "${languageCode}.traineddata")
                if (langFile.exists() && langFile.length() > 0) {
                    withContext(Dispatchers.Main) { result.success(true) }
                    return@launch
                }

                val url = "https://github.com/tesseract-ocr/tessdata_fast/raw/main/${languageCode}.traineddata"
                val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
                connection.connectTimeout = 30000
                connection.readTimeout = 60000
                connection.requestMethod = "GET"

                try {
                    if (connection.responseCode != 200) {
                        throw IllegalStateException("Failed to download language pack: HTTP ${connection.responseCode}")
                    }
                    val partFile = File(tessDataDir, "${languageCode}.traineddata.part")
                    connection.inputStream.use { input ->
                        partFile.outputStream().use { output -> input.copyTo(output) }
                    }
                    if (partFile.length() == 0L || !partFile.renameTo(langFile)) {
                        partFile.delete()
                        throw IllegalStateException("Language pack download was incomplete")
                    }
                } finally {
                    connection.disconnect()
                }

                withContext(Dispatchers.Main) { result.success(true) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("DOWNLOAD_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * Returns list of available (downloaded) language codes.
     */
    fun getAvailableLanguages(result: MethodChannel.Result) {
        val languages = tessDataDir.listFiles()
            ?.filter { it.name.endsWith(".traineddata") }
            ?.map { it.name.removeSuffix(".traineddata") }
            ?: emptyList()

        result.success(languages)
    }
}
