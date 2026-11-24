package com.docuscanpro.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.contentstream.operator.Operator
import com.tom_roush.pdfbox.cos.COSArray
import com.tom_roush.pdfbox.cos.COSBase
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.cos.COSNumber
import com.tom_roush.pdfbox.cos.COSStream
import com.tom_roush.pdfbox.cos.COSString
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.multipdf.PDFMergerUtility
import com.tom_roush.pdfbox.pdfparser.PDFStreamParser
import com.tom_roush.pdfbox.pdfwriter.ContentStreamWriter
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.PDResources
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.common.PDStream
import com.tom_roush.pdfbox.pdmodel.encryption.AccessPermission
import com.tom_roush.pdfbox.pdmodel.encryption.StandardProtectionPolicy
import com.tom_roush.pdfbox.pdmodel.font.PDFont
import com.tom_roush.pdfbox.pdmodel.font.PDType0Font
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font
import com.tom_roush.pdfbox.pdmodel.font.PDVectorFont
import com.tom_roush.pdfbox.pdmodel.graphics.form.PDFormXObject
import com.tom_roush.pdfbox.pdmodel.graphics.image.JPEGFactory
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import com.tom_roush.pdfbox.pdmodel.graphics.state.PDExtendedGraphicsState
import com.tom_roush.pdfbox.pdmodel.graphics.state.RenderingMode
import com.tom_roush.pdfbox.pdmodel.interactive.annotation.PDAnnotationText
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDButton
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDCheckBox
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDChoice
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDComboBox
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDField
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDPushButton
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDRadioButton
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDSignatureField
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDTerminalField
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDTextField
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.text.TextPosition
import com.tom_roush.pdfbox.util.Matrix
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.min

class PdfBoxHandler(private val context: Context) {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    init {
        PDFBoxResourceLoader.init(context)
    }

    /**
     * Runs [block] off the main thread and delivers its value (or an error with
     * [errorCode]) back on the main thread. Catches Throwable so that an
     * OutOfMemoryError on a huge page/image becomes a Dart error, not a crash.
     */
    private fun respond(result: MethodChannel.Result, errorCode: String, block: () -> Any?) {
        scope.launch {
            try {
                val value = block()
                withContext(Dispatchers.Main) { result.success(value) }
            } catch (e: Throwable) {
                withContext(Dispatchers.Main) {
                    result.error(errorCode, e.message ?: e.javaClass.simpleName, null)
                }
            }
        }
    }

    private fun outputPath(outputDir: String, prefix: String) =
        "$outputDir/${prefix}_${System.currentTimeMillis()}.pdf"

    private fun saveAndClose(doc: PDDocument, path: String): String {
        doc.use { it.save(File(path)) }
        return path
    }

    // ── Merge PDFs ──

    fun mergePdfs(pdfPaths: List<String>, outputName: String, outputDir: String, result: MethodChannel.Result) =
        respond(result, "MERGE_ERROR") {
            val outputPath = "$outputDir/${outputName}.pdf"
            val merger = PDFMergerUtility()
            pdfPaths.forEach { merger.addSource(File(it)) }
            merger.destinationFileName = outputPath
            // Temp-file backed so merging large documents doesn't exhaust the heap.
            merger.mergeDocuments(MemoryUsageSetting.setupTempFileOnly())
            outputPath
        }

    // ── Split PDF ──

    fun splitPdf(pdfPath: String, pageNumbers: List<Int>, outputDir: String, result: MethodChannel.Result) =
        respond(result, "SPLIT_ERROR") {
            PDDocument.load(File(pdfPath)).use { doc ->
                val newDoc = PDDocument()
                for (pageNum in pageNumbers.sorted()) {
                    if (pageNum >= 0 && pageNum < doc.numberOfPages) {
                        newDoc.importPage(doc.getPage(pageNum))
                    }
                }
                listOf(saveAndClose(newDoc, outputPath(outputDir, "split")))
            }
        }

    // ── Compress PDF ──

    /**
     * Downsamples and re-encodes embedded raster images as JPEG. Images are
     * capped at the pixel size needed to fill the page at [dpi], so an image is
     * never reduced below what the preset can display. Soft masks are carried
     * over; stencil and colour-key masked images and bilevel codecs
     * (CCITT/JBIG2, already tiny) are left alone. Vector content and text are
     * untouched.
     */
    fun compressPdf(pdfPath: String, quality: Int, dpi: Int, outputDir: String, result: MethodChannel.Result) =
        respond(result, "COMPRESS_ERROR") {
            val input = File(pdfPath)
            val out = outputPath(outputDir, "compressed")
            PDDocument.load(input).use { doc ->
                val done = HashMap<COSBase, PDImageXObject>()
                for (page in doc.pages) {
                    val box = page.cropBox
                    val maxW = (box.width / 72f * dpi).toInt().coerceAtLeast(1)
                    val maxH = (box.height / 72f * dpi).toInt().coerceAtLeast(1)
                    compressResources(doc, page.resources, maxW, maxH, quality / 100f, done, HashSet())
                }
                doc.save(File(out))
            }
            // Never hand back a file bigger than the original.
            if (File(out).length() >= input.length()) input.copyTo(File(out), overwrite = true)
            out
        }

    private fun compressResources(
        doc: PDDocument,
        resources: PDResources?,
        maxW: Int,
        maxH: Int,
        quality: Float,
        done: HashMap<COSBase, PDImageXObject>,
        visitedForms: HashSet<COSBase>
    ) {
        if (resources == null) return
        for (name in resources.xObjectNames.toList()) {
            val xObject = try { resources.getXObject(name) } catch (e: Exception) { null } ?: continue
            when (xObject) {
                is PDImageXObject -> {
                    val key = xObject.cosObject
                    val replacement = done.getOrPut(key) {
                        recompressImage(doc, xObject, maxW, maxH, quality) ?: xObject
                    }
                    if (replacement !== xObject) resources.put(name, replacement)
                }
                is PDFormXObject -> {
                    if (visitedForms.add(xObject.cosObject)) {
                        compressResources(doc, xObject.resources, maxW, maxH, quality, done, visitedForms)
                    }
                }
            }
        }
    }

    private fun recompressImage(doc: PDDocument, image: PDImageXObject, maxW: Int, maxH: Int, quality: Float): PDImageXObject? {
        val stream: COSStream = image.cosObject
        val filters = stream.filters.toString()
        if (image.isStencil || image.bitsPerComponent == 1) return null
        // Colour-key masks match exact colours, which JPEG doesn't preserve. Soft masks
        // (/SMask) are fine: they're kept as-is and re-attached below. The Dart `pdf`
        // package adds one to every image, including the app's own scans.
        if (stream.containsKey(COSName.MASK)) return null
        if ("CCITT" in filters || "JBIG2" in filters) return null
        val originalLength = stream.length
        if (originalLength < 8 * 1024) return null

        return try {
            val scale = min(1f, min(maxW.toFloat() / image.width, maxH.toFloat() / image.height))
            // Decode with subsampling first so a 6000px scan doesn't need a full-size bitmap.
            val subsampling = max(1, (1f / scale).toInt())
            val decoded = image.getImage(Rect(0, 0, image.width, image.height), subsampling) ?: return null
            val targetW = max(1, (image.width * scale).toInt())
            val targetH = max(1, (image.height * scale).toInt())
            val scaled = if (decoded.width != targetW || decoded.height != targetH) {
                Bitmap.createScaledBitmap(decoded, targetW, targetH, true).also { decoded.recycle() }
            } else decoded
            val rgb = if (scaled.hasAlpha()) flattenOnWhite(scaled).also { scaled.recycle() } else scaled
            val jpeg = JPEGFactory.createFromImage(doc, rgb, quality)
            rgb.recycle()
            // A soft mask may differ in resolution from its image (PDF 32000 §11.6.5.3),
            // so the original keeps transparency correct after downsampling.
            stream.getItem(COSName.SMASK)?.let { jpeg.cosObject.setItem(COSName.SMASK, it) }
            if (jpeg.cosObject.length < originalLength * 0.9) jpeg else null
        } catch (e: Throwable) {
            // Undecodable (e.g. JPX) or out of memory: keep the original image.
            android.util.Log.w("PdfBoxHandler", "Image not recompressed: ${e.message}", e)
            null
        }
    }

    private fun flattenOnWhite(src: Bitmap): Bitmap {
        val out = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(out)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(src, 0f, 0f, null)
        return out
    }

    // ── Encrypt PDF ──

    fun encryptPdf(
        pdfPath: String,
        password: String,
        allowPrinting: Boolean,
        allowCopying: Boolean,
        allowEditing: Boolean,
        outputDir: String,
        result: MethodChannel.Result
    ) = respond(result, "ENCRYPT_ERROR") {
        val doc = PDDocument.load(File(pdfPath))
        val accessPermission = AccessPermission()
        accessPermission.setCanPrint(allowPrinting)
        accessPermission.setCanExtractContent(allowCopying)
        accessPermission.setCanModify(allowEditing)

        // A distinct, random owner password: if it equalled the user password, anyone
        // who can open the file would get owner rights and the permissions would be moot.
        val ownerPassword = java.util.UUID.randomUUID().toString()
        val policy = StandardProtectionPolicy(ownerPassword, password, accessPermission)
        policy.encryptionKeyLength = 256
        doc.protect(policy)
        saveAndClose(doc, outputPath(outputDir, "protected"))
    }

    // ── Edit PDF Text ──

    /**
     * Replaces text on one page. Each replacement is first attempted in the page's
     * content stream, re-encoding with the original font so the font, size,
     * colour and position are preserved. When that isn't possible (text split
     * across operators, inside a form XObject, a subset font missing the new
     * glyphs, or a style change was requested), the original text is covered
     * with a white box and the new text is drawn on top in the closest standard
     * font at the original size.
     */
    fun editPdfText(
        pdfPath: String,
        pageIndex: Int,
        replacements: Map<String, String>,
        formatting: Map<String, Map<String, Any>>,
        outputDir: String,
        result: MethodChannel.Result
    ) = respond(result, "EDIT_ERROR") {
        val doc = PDDocument.load(File(pdfPath))
        try {
            if (pageIndex !in 0 until doc.numberOfPages) throw IllegalArgumentException("Page $pageIndex out of range")
            val page = doc.getPage(pageIndex)
            val pending = replacements.filter { (old, new) -> old.isNotBlank() && old != new }.toMutableMap()

            // A requested bold/italic change can't be expressed by re-encoding the original font.
            val styleChange = pending.keys.filter { key ->
                val f = formatting[key]
                f?.get("bold") == true || f?.get("italic") == true
            }.toSet()

            val inStream = pending.filterKeys { it !in styleChange && !it.contains('\n') }
            val replaced = replaceInContentStream(doc, page, inStream)
            pending.keys.removeAll(replaced)

            if (pending.isNotEmpty()) overlayReplacements(doc, page, pending, formatting)
            saveAndClose(doc, outputPath(outputDir, "edited"))
        } catch (e: Throwable) {
            doc.close()
            throw e
        }
    }

    private class FontState(var font: PDFont?)

    /** Returns the set of replacement keys that were applied in the content stream. */
    private fun replaceInContentStream(doc: PDDocument, page: PDPage, replacements: Map<String, String>): Set<String> {
        if (replacements.isEmpty()) return emptySet()
        val resources = page.resources ?: return emptySet()
        val parser = PDFStreamParser(page)
        parser.parse()
        val tokens: MutableList<Any> = parser.tokens

        // Pass 1: which characters does each font already draw on this page? A subset
        // font can only be trusted to contain glyphs it has already been used for.
        val usedChars = HashMap<PDFont, MutableSet<Int>>()
        walkTextOperators(tokens, resources) { font, _, text -> usedChars.getOrPut(font) { HashSet() }.addAll(text.codePoints().toArray().toList()) }

        // Pass 2: replace.
        val done = HashSet<String>()
        walkTextOperators(tokens, resources) { font, operandIndex, text ->
            for ((old, new) in replacements) {
                if (old in done || !text.contains(old)) continue
                val newText = text.replace(old, new)
                val encoded = encodeIfRenderable(font, newText, usedChars[font].orEmpty()) ?: continue
                // TJ takes an array operand; Tj/'/" take a string.
                tokens[operandIndex] = if (tokens[operandIndex] is COSArray) {
                    COSArray().apply { add(COSString(encoded)) }
                } else COSString(encoded)
                done.add(old)
                break
            }
        }
        if (done.isEmpty()) return done

        val newContents = PDStream(doc)
        newContents.createOutputStream(COSName.FLATE_DECODE).use { ContentStreamWriter(it).writeTokens(tokens) }
        page.setContents(newContents)
        return done
    }

    /**
     * Visits every text-showing operator (Tj, ', ", TJ) with the font in effect
     * and the decoded text. For TJ, large negative kerning gaps are decoded as
     * spaces so "Hello World" set as [(Hello) -250 (World)] still matches.
     */
    private fun walkTextOperators(
        tokens: List<Any>,
        resources: PDResources,
        visit: (font: PDFont, operandIndex: Int, text: String) -> Unit
    ) {
        val stack = ArrayDeque<PDFont?>()
        val state = FontState(null)
        for (i in tokens.indices) {
            val op = tokens[i] as? Operator ?: continue
            when (op.name) {
                "q" -> stack.addLast(state.font)
                "Q" -> state.font = stack.removeLastOrNull() ?: state.font
                "Tf" -> {
                    val name = tokens.getOrNull(i - 2) as? COSName
                    state.font = name?.let { try { resources.getFont(it) } catch (e: Exception) { null } }
                }
                "Tj", "'", "\"" -> {
                    val font = state.font ?: continue
                    val str = tokens.getOrNull(i - 1) as? COSString ?: continue
                    val text = decode(font, str.bytes) ?: continue
                    visit(font, i - 1, text)
                }
                "TJ" -> {
                    val font = state.font ?: continue
                    val array = tokens.getOrNull(i - 1) as? COSArray ?: continue
                    val sb = StringBuilder()
                    var ok = true
                    for (element in array) {
                        when (element) {
                            is COSString -> sb.append(decode(font, element.bytes) ?: run { ok = false; "" })
                            is COSNumber -> if (element.floatValue() < -200f && sb.isNotEmpty() && sb.last() != ' ') sb.append(' ')
                        }
                    }
                    if (!ok) continue
                    // Replacing collapses the TJ array into one string: kerning within the
                    // matched run is lost, which is visually negligible for body text.
                    val operandIndex = i - 1
                    visit(font, operandIndex, sb.toString())
                }
            }
        }
    }

    private fun decode(font: PDFont, bytes: ByteArray): String? {
        val input = ByteArrayInputStream(bytes)
        val sb = StringBuilder()
        while (input.available() > 0) {
            val code = font.readCode(input)
            sb.append(font.toUnicode(code) ?: return null)
        }
        return sb.toString()
    }

    private fun encodeIfRenderable(font: PDFont, text: String, alreadyUsed: Set<Int>): ByteArray? {
        val isSubset = font.name?.matches(Regex("^[A-Z]{6}\\+.*")) == true
        return try {
            val bytes = font.encode(text)
            if (font is PDVectorFont) {
                val input = ByteArrayInputStream(bytes)
                while (input.available() > 0) if (!font.hasGlyph(font.readCode(input))) return null
            }
            if (isSubset && text.codePoints().anyMatch { it !in alreadyUsed }) return null
            bytes
        } catch (e: Exception) {
            null
        }
    }

    /** Collects every glyph position on a page along with the page text, aligned index-for-index. */
    private class PositionCollector(pageNumber: Int) : PDFTextStripper() {
        val text = StringBuilder()
        val positions = ArrayList<TextPosition?>()

        init {
            sortByPosition = true
            startPage = pageNumber
            endPage = pageNumber
        }

        override fun writeString(string: String, textPositions: MutableList<TextPosition>) {
            for (tp in textPositions) {
                val unicode = tp.unicode ?: continue
                for (ch in unicode) {
                    text.append(ch)
                    positions.add(tp)
                }
            }
        }

        override fun writeWordSeparator() {
            text.append(' '); positions.add(null)
        }

        override fun writeLineSeparator() {
            text.append('\n'); positions.add(null)
        }
    }

    private fun overlayReplacements(
        doc: PDDocument,
        page: PDPage,
        replacements: Map<String, String>,
        formatting: Map<String, Map<String, Any>>
    ) {
        val collector = PositionCollector(doc.pages.indexOf(page) + 1)
        collector.getText(doc)
        // Whitespace-insensitive search: collapse runs of whitespace on both sides.
        val normalized = StringBuilder()
        val normPositions = ArrayList<TextPosition?>()
        for (i in collector.text.indices) {
            val ch = collector.text[i]
            if (ch.isWhitespace()) {
                if (normalized.isNotEmpty() && normalized.last() != ' ') { normalized.append(' '); normPositions.add(null) }
            } else {
                normalized.append(ch); normPositions.add(collector.positions[i])
            }
        }

        PDPageContentStream(doc, page, PDPageContentStream.AppendMode.APPEND, true, true).use { cs ->
            for ((old, new) in replacements) {
                val oldLines = old.split('\n').map { it.trim().replace(Regex("\\s+"), " ") }.filter { it.isNotEmpty() }
                val newLines = new.split('\n')
                val style = formatting[old]
                var searchFrom = 0
                oldLines.forEachIndexed { lineIndex, oldLine ->
                    val at = normalized.indexOf(oldLine, searchFrom)
                    if (at < 0) throw IllegalStateException("Couldn't find \"$oldLine\" on this page")
                    searchFrom = at + oldLine.length
                    val glyphs = (at until at + oldLine.length).mapNotNull { normPositions[it] }
                    if (glyphs.isEmpty()) return@forEachIndexed
                    // Spread the new lines over the old ones; any extra new lines join the last.
                    val replacement = when {
                        lineIndex < oldLines.lastIndex -> newLines.getOrElse(lineIndex) { "" }
                        else -> newLines.drop(lineIndex).joinToString(" ")
                    }
                    drawReplacement(doc, cs, glyphs, replacement, style)
                }
            }
        }
    }

    private fun drawReplacement(
        doc: PDDocument,
        cs: PDPageContentStream,
        glyphs: List<TextPosition>,
        text: String,
        style: Map<String, Any>?
    ) {
        val first = glyphs.first()
        val fontSize = first.fontSizeInPt.takeIf { it > 0f } ?: (style?.get("fontSize") as? Number)?.toFloat() ?: 12f
        val left = glyphs.minOf { it.textMatrix.translateX }
        val right = glyphs.maxOf { it.textMatrix.translateX + it.widthDirAdj }
        val baseline = glyphs.minOf { it.textMatrix.translateY }
        val descent = fontSize * 0.25f
        val ascent = max(fontSize * 0.9f, glyphs.maxOf { it.heightDir })

        cs.setNonStrokingColor(1f, 1f, 1f)
        cs.addRect(left - 1f, baseline - descent, right - left + 2f, ascent + descent + 1f)
        cs.fill()

        if (text.isEmpty()) return
        val originalName = first.font?.name.orEmpty()
        val bold = style?.get("bold") == true || originalName.contains("Bold", ignoreCase = true)
        val italic = style?.get("italic") == true ||
            originalName.contains("Italic", ignoreCase = true) || originalName.contains("Oblique", ignoreCase = true)
        val font = fontFor(doc, text, closestStandardFont(originalName, bold, italic))

        cs.setNonStrokingColor(0f, 0f, 0f)
        cs.beginText()
        cs.setFont(font, fontSize)
        cs.newLineAtOffset(left, baseline)
        cs.showText(text)
        cs.endText()
    }

    private fun closestStandardFont(originalName: String, bold: Boolean, italic: Boolean): PDType1Font {
        val n = originalName.lowercase()
        return when {
            "courier" in n || "mono" in n -> when {
                bold && italic -> PDType1Font.COURIER_BOLD_OBLIQUE
                bold -> PDType1Font.COURIER_BOLD
                italic -> PDType1Font.COURIER_OBLIQUE
                else -> PDType1Font.COURIER
            }
            "times" in n || "serif" in n && "sans" !in n || "georgia" in n || "garamond" in n -> when {
                bold && italic -> PDType1Font.TIMES_BOLD_ITALIC
                bold -> PDType1Font.TIMES_BOLD
                italic -> PDType1Font.TIMES_ITALIC
                else -> PDType1Font.TIMES_ROMAN
            }
            else -> when {
                bold && italic -> PDType1Font.HELVETICA_BOLD_OBLIQUE
                bold -> PDType1Font.HELVETICA_BOLD
                italic -> PDType1Font.HELVETICA_OBLIQUE
                else -> PDType1Font.HELVETICA
            }
        }
    }

    private var unicodeFontCache: Pair<PDDocument, PDFont?>? = null

    /**
     * Standard-14 fonts only cover WinAnsi (Western European). For anything else
     * embed a system font that covers Latin, Greek and Cyrillic at least.
     */
    private fun unicodeFont(doc: PDDocument): PDFont? {
        unicodeFontCache?.let { (cachedDoc, font) -> if (cachedDoc === doc) return font }
        val candidates = listOf(
            "/system/fonts/Roboto-Regular.ttf",
            "/system/fonts/NotoSans-Regular.ttf",
            "/system/fonts/DroidSans.ttf"
        )
        val font = candidates.map(::File).firstOrNull { it.exists() }?.let {
            try { PDType0Font.load(doc, it) } catch (e: Exception) { null }
        }
        unicodeFontCache = doc to font
        return font
    }

    private fun canEncode(font: PDFont, text: String) = try { font.encode(text); true } catch (e: Exception) { false }

    private fun fontFor(doc: PDDocument, text: String, preferred: PDFont): PDFont =
        if (canEncode(preferred, text)) preferred else unicodeFont(doc) ?: preferred

    // ── Insert Pages ──

    /** [pagePaths] may be PDFs (all pages inserted) or images (one page each, sized to the image). */
    fun insertPages(pdfPath: String, insertAtIndex: Int, pagePaths: List<String>, outputDir: String, result: MethodChannel.Result) =
        respond(result, "INSERT_ERROR") {
            val doc = PDDocument.load(File(pdfPath))
            val sources = ArrayList<PDDocument>()
            try {
                var currentIndex = insertAtIndex.coerceIn(0, doc.numberOfPages)
                for (path in pagePaths) {
                    val newPages = if (path.lowercase().endsWith(".pdf")) {
                        val source = PDDocument.load(File(path)).also { sources.add(it) }
                        source.pages.map { doc.importPage(it) }
                    } else {
                        listOf(imagePage(doc, path))
                    }
                    for (page in newPages) {
                        // importPage/addPage append at the end; move into position.
                        doc.pages.remove(page)
                        if (currentIndex < doc.numberOfPages) doc.pages.insertBefore(page, doc.getPage(currentIndex))
                        else doc.pages.add(page)
                        currentIndex++
                    }
                }
                val out = outputPath(outputDir, "inserted")
                doc.save(File(out))
                out
            } finally {
                doc.close()
                sources.forEach { it.close() }
            }
        }

    private fun imagePage(doc: PDDocument, imagePath: String): PDPage {
        val image = PDImageXObject.createFromFile(imagePath, doc)
        // Fit the image onto an A4 page at its aspect ratio.
        val a4 = PDRectangle.A4
        val scale = min(a4.width / image.width, a4.height / image.height)
        val w = image.width * scale
        val h = image.height * scale
        val page = PDPage(a4)
        doc.addPage(page)
        PDPageContentStream(doc, page).use { it.drawImage(image, (a4.width - w) / 2, (a4.height - h) / 2, w, h) }
        return page
    }

    // ── Reorder Pages ──

    fun reorderPages(pdfPath: String, newOrder: List<Int>, outputDir: String, result: MethodChannel.Result) =
        respond(result, "REORDER_ERROR") {
            val doc = PDDocument.load(File(pdfPath))
            // Reorder within the same document so outlines, forms and metadata survive.
            val pages = (0 until doc.numberOfPages).map { doc.getPage(it) }
            pages.forEach { doc.pages.remove(it) }
            newOrder.filter { it in pages.indices }.forEach { doc.pages.add(pages[it]) }
            saveAndClose(doc, outputPath(outputDir, "reordered"))
        }

    // ── Delete Pages ──

    fun deletePages(pdfPath: String, pageIndices: List<Int>, outputDir: String, result: MethodChannel.Result) =
        respond(result, "DELETE_ERROR") {
            val doc = PDDocument.load(File(pdfPath))
            // Remove pages in reverse order to maintain indices
            for (index in pageIndices.distinct().sortedDescending()) {
                if (index >= 0 && index < doc.numberOfPages) doc.removePage(index)
            }
            saveAndClose(doc, outputPath(outputDir, "trimmed"))
        }

    // ── Rotate Pages ──

    fun rotatePages(pdfPath: String, pageIndices: List<Int>, degrees: Int, outputDir: String, result: MethodChannel.Result) =
        respond(result, "ROTATE_ERROR") {
            val doc = PDDocument.load(File(pdfPath))
            for (index in pageIndices) {
                if (index >= 0 && index < doc.numberOfPages) {
                    val page = doc.getPage(index)
                    page.rotation = ((page.rotation + degrees) % 360 + 360) % 360
                }
            }
            saveAndClose(doc, outputPath(outputDir, "rotated"))
        }

    // ── Add Image to PDF (Signatures) ──

    fun addImageToPdf(
        pdfPath: String,
        pageIndex: Int,
        imageBytes: ByteArray,
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        outputDir: String,
        result: MethodChannel.Result
    ) = respond(result, "ADD_IMAGE_ERROR") {
        val doc = PDDocument.load(File(pdfPath))
        val page = doc.getPage(pageIndex)
        val pdImage = PDImageXObject.createFromByteArray(doc, imageBytes, "signature")
        PDPageContentStream(doc, page, PDPageContentStream.AppendMode.APPEND, true, true).use {
            it.drawImage(pdImage, x, page.mediaBox.height - y - height, width, height)
        }
        saveAndClose(doc, outputPath(outputDir, "signed"))
    }

    // ── Add Text to PDF ──

    fun addTextToPdf(
        pdfPath: String,
        pageIndex: Int,
        text: String,
        x: Float,
        y: Float,
        fontSize: Float,
        outputDir: String,
        result: MethodChannel.Result
    ) = respond(result, "ADD_TEXT_ERROR") {
        val doc = PDDocument.load(File(pdfPath))
        val page = doc.getPage(pageIndex)
        PDPageContentStream(doc, page, PDPageContentStream.AppendMode.APPEND, true, true).use {
            it.beginText()
            it.setFont(fontFor(doc, text, PDType1Font.HELVETICA), fontSize)
            it.newLineAtOffset(x, page.mediaBox.height - y)
            it.showText(text)
            it.endText()
        }
        saveAndClose(doc, outputPath(outputDir, "text"))
    }

    // ── Form Fields ──

    fun getFormFields(pdfPath: String, result: MethodChannel.Result) = respond(result, "FORM_ERROR") {
        PDDocument.load(File(pdfPath)).use { doc ->
            val form = doc.documentCatalog.acroForm ?: return@use emptyList<Map<String, Any>>()
            form.fieldTree.filterIsInstance<PDTerminalField>()
                .filter { it !is PDPushButton }
                .map { field ->
                    val widgetPage = field.widgets.firstOrNull()?.page
                    mapOf(
                        "name" to field.fullyQualifiedName,
                        "type" to fieldType(field),
                        "value" to (field.valueAsString ?: ""),
                        "page" to (widgetPage?.let { doc.pages.indexOf(it) }?.coerceAtLeast(0) ?: 0),
                        "options" to fieldOptions(field)
                    )
                }
        }
    }

    private fun fieldType(field: PDField) = when (field) {
        is PDTextField -> "text"
        is PDCheckBox -> "checkbox"
        is PDRadioButton -> "radio"
        is PDComboBox -> "dropdown"
        is PDChoice -> "list"
        is PDSignatureField -> "signature"
        else -> "text"
    }

    private fun fieldOptions(field: PDField): List<String> = when (field) {
        is PDChoice -> field.optionsExportValues
        is PDCheckBox -> listOfNotNull(field.onValue)
        is PDButton -> field.onValues.toList()
        else -> emptyList()
    }

    fun fillFormFields(pdfPath: String, fieldValues: Map<String, String>, outputDir: String, result: MethodChannel.Result) =
        respond(result, "FORM_ERROR") {
            val doc = PDDocument.load(File(pdfPath))
            try {
                val form = doc.documentCatalog.acroForm ?: throw IllegalStateException("This PDF has no fillable form fields")
                // Hybrid AcroForm/XFA documents: drop XFA so viewers show the AcroForm values we set.
                form.xfa = null
                for ((name, value) in fieldValues) {
                    val field = form.getField(name) ?: continue
                    when (field) {
                        is PDCheckBox -> if (value.isTruthy() || value == field.onValue) field.check() else field.unCheck()
                        is PDButton -> if (value.isNotEmpty()) field.setValue(value)
                        is PDSignatureField -> Unit // Signatures are placed as images via addImageToPdf.
                        else -> field.setValue(value)
                    }
                }
                saveAndClose(doc, outputPath(outputDir, "filled"))
            } catch (e: Throwable) {
                doc.close()
                throw e
            }
        }

    private fun String.isTruthy() = trim().lowercase() in setOf("true", "yes", "on", "1", "x", "checked")

    // ── Annotations ──

    /**
     * Writes annotations drawn in the Flutter overlay into the PDF. Coordinates
     * arrive normalised (0–1) relative to the page as displayed (top-left origin,
     * page rotation applied). Highlights, underlines, strikethroughs, ink and text
     * notes are flattened into the page content; sticky notes become real PDF
     * text annotations so they stay collapsible in any viewer.
     */
    fun applyAnnotations(pdfPath: String, annotations: List<Map<String, Any?>>, outputDir: String, result: MethodChannel.Result) =
        respond(result, "ANNOTATION_ERROR") {
            val doc = PDDocument.load(File(pdfPath))
            try {
                annotations.groupBy { (it["pageIndex"] as Number).toInt() }.forEach { (pageIndex, pageAnnotations) ->
                    if (pageIndex !in 0 until doc.numberOfPages) return@forEach
                    val page = doc.getPage(pageIndex)
                    val mapper = DisplayMapper(page)
                    PDPageContentStream(doc, page, PDPageContentStream.AppendMode.APPEND, true, true).use { cs ->
                        for (a in pageAnnotations) drawAnnotation(doc, page, cs, mapper, a)
                    }
                }
                saveAndClose(doc, outputPath(outputDir, "annotated"))
            } catch (e: Throwable) {
                doc.close()
                throw e
            }
        }

    /** Maps display coordinates (top-left origin, rotation applied) to PDF user space. */
    private class DisplayMapper(page: PDPage) {
        val box: PDRectangle = page.cropBox
        val rotation = ((page.rotation % 360) + 360) % 360
        val displayWidth = if (rotation == 90 || rotation == 270) box.height else box.width
        val displayHeight = if (rotation == 90 || rotation == 270) box.width else box.height

        /** Normalised display point → user space point. */
        fun map(nx: Double, ny: Double): Pair<Float, Float> {
            val dx = (nx * displayWidth).toFloat()
            val dy = (ny * displayHeight).toFloat()
            val (u, v) = when (rotation) {
                90 -> dy to dx
                180 -> (box.width - dx) to dy
                270 -> (box.width - dy) to (box.height - dx)
                else -> dx to (box.height - dy)
            }
            return (box.lowerLeftX + u) to (box.lowerLeftY + v)
        }

        /** Angle (degrees) that makes text run left-to-right as displayed. */
        val textAngle get() = rotation.toDouble()

        /** Points per normalised display unit (for stroke widths and font sizes). */
        val scale get() = displayWidth
    }

    private fun drawAnnotation(doc: PDDocument, page: PDPage, cs: PDPageContentStream, m: DisplayMapper, a: Map<String, Any?>) {
        val type = a["type"] as? String ?: return
        val argb = (a["color"] as? Number)?.toLong() ?: 0xFFFFEB3BL
        val r = ((argb shr 16) and 0xFF) / 255f
        val g = ((argb shr 8) and 0xFF) / 255f
        val b = (argb and 0xFF) / 255f
        @Suppress("UNCHECKED_CAST")
        val rect = a["rect"] as? Map<String, Number>
        @Suppress("UNCHECKED_CAST")
        val points = (a["points"] as? List<Map<String, Number>>).orEmpty()
        val strokeWidth = (a["strokeWidth"] as? Number)?.toFloat() ?: 2f
        val text = a["text"] as? String

        fun corner(x: Double, y: Double) = m.map(x, y)

        when (type) {
            "highlight", "underline", "strikethrough" -> {
                rect ?: return
                val x = rect["x"]!!.toDouble(); val y = rect["y"]!!.toDouble()
                val w = rect["width"]!!.toDouble(); val h = rect["height"]!!.toDouble()
                if (type == "highlight") {
                    cs.saveGraphicsState()
                    val gs = PDExtendedGraphicsState().apply {
                        nonStrokingAlphaConstant = 0.35f
                        blendMode = com.tom_roush.pdfbox.pdmodel.graphics.blend.BlendMode.MULTIPLY
                    }
                    cs.setGraphicsStateParameters(gs)
                    cs.setNonStrokingColor(r, g, b)
                    polygon(cs, listOf(corner(x, y), corner(x + w, y), corner(x + w, y + h), corner(x, y + h)))
                    cs.fill()
                    cs.restoreGraphicsState()
                } else {
                    val lineY = if (type == "underline") y + h else y + h / 2
                    cs.saveGraphicsState()
                    cs.setStrokingColor(r, g, b)
                    cs.setLineWidth(max(1f, (h * m.displayHeight * 0.08).toFloat()))
                    val (x0, y0) = corner(x, lineY); val (x1, y1) = corner(x + w, lineY)
                    cs.moveTo(x0, y0); cs.lineTo(x1, y1); cs.stroke()
                    cs.restoreGraphicsState()
                }
            }
            "freehand" -> {
                if (points.size < 2) return
                cs.saveGraphicsState()
                cs.setStrokingColor(r, g, b)
                // strokeWidth is in logical pixels of the on-screen page; normalise by its width.
                val viewWidth = (a["viewWidth"] as? Number)?.toFloat() ?: 360f
                cs.setLineWidth(strokeWidth * m.scale / viewWidth)
                cs.setLineCapStyle(1); cs.setLineJoinStyle(1)
                val (sx, sy) = corner(points[0]["x"]!!.toDouble(), points[0]["y"]!!.toDouble())
                cs.moveTo(sx, sy)
                for (p in points.drop(1)) {
                    val (px, py) = corner(p["x"]!!.toDouble(), p["y"]!!.toDouble())
                    cs.lineTo(px, py)
                }
                cs.stroke()
                cs.restoreGraphicsState()
            }
            "textNote" -> {
                if (text.isNullOrBlank() || rect == null) return
                val fontSize = 12f
                val font = fontFor(doc, text, PDType1Font.HELVETICA)
                val (ox, oy) = corner(rect["x"]!!.toDouble(), rect["y"]!!.toDouble())
                cs.saveGraphicsState()
                cs.setNonStrokingColor(r, g, b)
                cs.beginText()
                cs.setFont(font, fontSize)
                text.lines().forEachIndexed { i, line ->
                    // Each line sits one leading below the tap point, as displayed.
                    val rad = Math.toRadians(m.textAngle)
                    val drop = fontSize * 1.2f * (i + 1)
                    val tx = ox + (Math.sin(rad) * drop).toFloat()
                    val ty = oy - (Math.cos(rad) * drop).toFloat()
                    cs.setTextMatrix(Matrix.getRotateInstance(rad, tx, ty))
                    cs.showText(line)
                }
                cs.endText()
                cs.restoreGraphicsState()
            }
            "stickyNote" -> {
                if (rect == null) return
                val (px, py) = corner(rect["x"]!!.toDouble(), rect["y"]!!.toDouble())
                val note = PDAnnotationText()
                note.contents = text ?: ""
                note.name = PDAnnotationText.NAME_NOTE
                note.rectangle = PDRectangle(px, py - 20f, 20f, 20f)
                note.color = com.tom_roush.pdfbox.pdmodel.graphics.color.PDColor(
                    floatArrayOf(r, g, b), com.tom_roush.pdfbox.pdmodel.graphics.color.PDDeviceRGB.INSTANCE
                )
                note.constructAppearances()
                page.annotations = page.annotations.apply { add(note) }
            }
        }
    }

    private fun polygon(cs: PDPageContentStream, corners: List<Pair<Float, Float>>) {
        cs.moveTo(corners[0].first, corners[0].second)
        for (c in corners.drop(1)) cs.lineTo(c.first, c.second)
        cs.closePath()
    }

    // ── OCR Text Layer ──

    /**
     * Adds an invisible, selectable text layer from OCR results so scanned pages
     * become searchable. Line boxes arrive in pixel coordinates of the rendered
     * page image (top-left origin, rotation applied). Each line is stretched
     * horizontally to span its box so selection highlights line up with the image.
     */
    fun addOcrTextLayer(pdfPath: String, pages: List<Map<String, Any?>>, outputDir: String, result: MethodChannel.Result) =
        respond(result, "OCR_LAYER_ERROR") {
            val doc = PDDocument.load(File(pdfPath))
            try {
                for (pageData in pages) {
                    val pageIndex = (pageData["pageIndex"] as Number).toInt()
                    if (pageIndex !in 0 until doc.numberOfPages) continue
                    val imageWidth = (pageData["imageWidth"] as Number).toDouble()
                    val imageHeight = (pageData["imageHeight"] as Number).toDouble()
                    @Suppress("UNCHECKED_CAST")
                    val lines = (pageData["lines"] as? List<Map<String, Any?>>).orEmpty()
                    if (lines.isEmpty() || imageWidth <= 0 || imageHeight <= 0) continue

                    val page = doc.getPage(pageIndex)
                    val m = DisplayMapper(page)
                    PDPageContentStream(doc, page, PDPageContentStream.AppendMode.APPEND, true, true).use { cs ->
                        cs.beginText()
                        cs.setRenderingMode(RenderingMode.NEITHER)
                        for (line in lines) {
                            val raw = (line["text"] as? String)?.trim().orEmpty()
                            if (raw.isEmpty()) continue
                            val left = (line["left"] as Number).toDouble() / imageWidth
                            val top = (line["top"] as Number).toDouble() / imageHeight
                            val width = (line["width"] as Number).toDouble() / imageWidth
                            val height = (line["height"] as Number).toDouble() / imageHeight
                            val font = fontFor(doc, raw, PDType1Font.HELVETICA)
                            val text = encodableSubset(font, raw)
                            if (text.isBlank()) continue

                            val heightPt = (height * m.displayHeight).toFloat()
                            val widthPt = (width * m.displayWidth).toFloat()
                            val fontSize = max(1f, heightPt * 0.85f)
                            val natural = font.getStringWidth(text) / 1000f * fontSize
                            val hScale = if (natural > 0f) widthPt / natural else 1f
                            // Baseline sits ~20% of the box height above the box bottom.
                            val (bx, by) = m.map(left, top + height * 0.8)
                            val rad = Math.toRadians(m.textAngle)
                            val cos = Math.cos(rad).toFloat(); val sin = Math.sin(rad).toFloat()
                            cs.setFont(font, fontSize)
                            cs.setTextMatrix(Matrix(hScale * cos, hScale * sin, -sin, cos, bx, by))
                            cs.showText(text)
                        }
                        cs.endText()
                    }
                }
                saveAndClose(doc, outputPath(outputDir, "searchable"))
            } catch (e: Throwable) {
                doc.close()
                throw e
            }
        }

    /** Drops characters the font can't encode (e.g. CJK with a Latin fallback font). */
    private fun encodableSubset(font: PDFont, text: String): String {
        if (canEncode(font, text)) return text
        val sb = StringBuilder()
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            val ch = String(Character.toChars(cp))
            if (canEncode(font, ch)) sb.append(ch) else sb.append(' ')
            i += Character.charCount(cp)
        }
        return sb.toString()
    }

    // ── PDF to Images ──

    fun pdfToImages(pdfPath: String, format: String, dpi: Int, outputDir: String, result: MethodChannel.Result) =
        respond(result, "PDF_TO_IMAGES_ERROR") {
            val fd = ParcelFileDescriptor.open(File(pdfPath), ParcelFileDescriptor.MODE_READ_ONLY)
            val renderer = try { PdfRenderer(fd) } catch (e: SecurityException) {
                fd.close()
                throw IllegalStateException("This PDF is password protected")
            }
            val imagePaths = mutableListOf<String>()
            val stamp = System.currentTimeMillis()
            try {
                for (i in 0 until renderer.pageCount) {
                    renderer.openPage(i).use { page ->
                        var scale = dpi / 72f
                        // Cap at ~24 MP per page so a large-format page can't exhaust the heap.
                        val maxPixels = 24_000_000f
                        val pixels = page.width * scale * page.height * scale
                        if (pixels > maxPixels) scale *= Math.sqrt((maxPixels / pixels).toDouble()).toFloat()
                        val width = (page.width * scale).toInt().coerceAtLeast(1)
                        val height = (page.height * scale).toInt().coerceAtLeast(1)
                        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                        // PdfRenderer leaves the background transparent, which turns black in JPEG.
                        bitmap.eraseColor(Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)

                        val ext = if (format == "jpg" || format == "jpeg") "jpg" else "png"
                        val imagePath = "$outputDir/page_${stamp}_${i + 1}.$ext"
                        FileOutputStream(imagePath).use { out ->
                            val compressFormat = if (ext == "jpg") Bitmap.CompressFormat.JPEG else Bitmap.CompressFormat.PNG
                            bitmap.compress(compressFormat, 90, out)
                        }
                        bitmap.recycle()
                        imagePaths.add(imagePath)
                    }
                }
            } finally {
                renderer.close()
                fd.close()
            }
            imagePaths
        }

    // ── Get PDF Info ──

    fun getPdfInfo(pdfPath: String, result: MethodChannel.Result) = respond(result, "INFO_ERROR") {
        PDDocument.load(File(pdfPath)).use { doc ->
            mapOf(
                "pageCount" to doc.numberOfPages,
                "title" to (doc.documentInformation?.title ?: ""),
                "author" to (doc.documentInformation?.author ?: ""),
                "isEncrypted" to doc.isEncrypted
            )
        }
    }

    // ── Flatten Annotations ──

    /**
     * Burns every visible annotation's appearance into the page content and
     * removes the annotation, so markup can no longer be edited or hidden.
     * Annotations without an appearance stream (rare) are kept as-is.
     */
    fun flattenAnnotations(pdfPath: String, outputDir: String, result: MethodChannel.Result) =
        respond(result, "FLATTEN_ERROR") {
            val doc = PDDocument.load(File(pdfPath))
            try {
                doc.documentCatalog.acroForm?.let { form ->
                    form.refreshAppearances()
                    form.flatten()
                }
                for (page in doc.pages) {
                    val annotations = page.annotations
                    val kept = annotations.toMutableList()
                    PDPageContentStream(doc, page, PDPageContentStream.AppendMode.APPEND, true, true).use { cs ->
                        for (annotation in annotations) {
                            if (annotation.subtype == "Link" || annotation.subtype == "Popup") continue
                            if (annotation.isHidden || annotation.isNoView) { kept.remove(annotation); continue }
                            val ap = annotation.normalAppearanceStream ?: continue
                            val bbox = ap.bBox ?: continue
                            val rect = annotation.rectangle ?: continue
                            // Fit the appearance's transformed bbox onto the annotation rect (PDF 32000 §12.5.5).
                            val am = ap.matrix
                            val xs = listOf(bbox.lowerLeftX, bbox.upperRightX)
                            val ys = listOf(bbox.lowerLeftY, bbox.upperRightY)
                            val tx = xs.flatMap { x -> ys.map { y -> am.scaleX * x + am.shearX * y + am.translateX } }
                            val ty = xs.flatMap { x -> ys.map { y -> am.shearY * x + am.scaleY * y + am.translateY } }
                            val tbw = tx.max() - tx.min(); val tbh = ty.max() - ty.min()
                            if (tbw <= 0f || tbh <= 0f) continue
                            val a = Matrix.getTranslateInstance(rect.lowerLeftX, rect.lowerLeftY)
                            a.concatenate(Matrix.getScaleInstance(rect.width / tbw, rect.height / tbh))
                            a.concatenate(Matrix.getTranslateInstance(-tx.min(), -ty.min()))
                            cs.saveGraphicsState()
                            cs.transform(a)
                            cs.drawForm(ap)
                            cs.restoreGraphicsState()
                            kept.remove(annotation)
                        }
                    }
                    page.annotations = kept
                }
                saveAndClose(doc, outputPath(outputDir, "flattened"))
            } catch (e: Throwable) {
                doc.close()
                throw e
            }
        }

    // ── Extract PDF Content (for conversion) ──

    fun extractPdfContent(pdfPath: String, result: MethodChannel.Result) = respond(result, "EXTRACT_ERROR") {
        PDDocument.load(File(pdfPath)).use { doc ->
            val stripper = PDFTextStripper()
            val pages = mutableListOf<Map<String, Any>>()
            for (i in 0 until doc.numberOfPages) {
                stripper.startPage = i + 1
                stripper.endPage = i + 1
                pages.add(mapOf("text" to stripper.getText(doc), "pageIndex" to i))
            }
            mapOf("pages" to pages)
        }
    }
}
