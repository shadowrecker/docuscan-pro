package com.docuscanpro.app

import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * Handles cloud-based file conversion via the DocuScan Pro Cloud Run microservice.
 * Used as fallback for complex PDF layouts that the on-device engine can't handle.
 * Files are deleted from the server within 60 seconds of conversion.
 */
class CloudConversionHandler {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    fun convert(
        fileContent: String, // Base64-encoded file content
        sourceFormat: String,
        targetFormat: String,
        baseUrl: String,
        apiKey: String?,
        result: MethodChannel.Result
    ) {
        scope.launch {
            try {
                val url = URL(baseUrl)
                val connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.setRequestProperty("Content-Type", "application/json")
                if (!apiKey.isNullOrEmpty()) connection.setRequestProperty("X-Api-Key", apiKey)
                connection.connectTimeout = 120000 // 2 minutes
                connection.readTimeout = 120000
                connection.doOutput = true

                val requestBody = JSONObject().apply {
                    put("file", fileContent)
                    put("sourceFormat", sourceFormat)
                    put("targetFormat", targetFormat)
                }

                val writer = OutputStreamWriter(connection.outputStream)
                writer.write(requestBody.toString())
                writer.flush()
                writer.close()

                if (connection.responseCode == 200) {
                    val response = connection.inputStream.bufferedReader().readText()
                    val json = JSONObject(response)

                    val resultMap = mapOf(
                        "content" to json.getString("content"),
                        "format" to json.getString("format")
                    )

                    withContext(Dispatchers.Main) {
                        result.success(resultMap)
                    }
                } else {
                    // The server returns {"error": "..."} on failure.
                    val body = connection.errorStream?.bufferedReader()?.readText()
                    val error = body?.let { runCatching { JSONObject(it).optString("error") }.getOrNull() }
                        ?.takeIf { it.isNotEmpty() } ?: "HTTP ${connection.responseCode}"

                    withContext(Dispatchers.Main) {
                        result.error(
                            "CLOUD_CONVERSION_ERROR",
                            "Cloud conversion failed: $error",
                            null
                        )
                    }
                }

                connection.disconnect()
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("CLOUD_CONVERSION_ERROR", e.message, null)
                }
            }
        }
    }
}
