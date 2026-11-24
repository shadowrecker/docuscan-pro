import CoreGraphics
import CoreText
import Flutter
import ImageIO
import PDFKit
#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformBezierPath = UIBezierPath
extension NSValue {
    convenience init(point: CGPoint) { self.init(cgPoint: point) }
}
#else
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformBezierPath = NSBezierPath
extension NSBezierPath {
    func addLine(to point: CGPoint) { line(to: point) }
}
#endif

/// Handles PDF operations on iOS using PDFKit (native) and CoreGraphics.
/// Maps to the same method channel as the Android PDFBox implementation.
///
/// PDFKit can't edit page content streams, so operations that must change what
/// a page draws (signatures, text edits, OCR text layers) re-render that one page
/// through a Quartz PDF context: the original content is replayed as vectors and
/// text, the overlay is drawn on top, and the page's annotations, crop box and
/// rotation are carried over. Other pages are untouched.
class PdfHandler: NSObject {

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            switch call.method {
            case "mergePdfs":
                self.mergePdfs(args: args, result: result)
            case "splitPdf":
                self.splitPdf(args: args, result: result)
            case "compressPdf":
                self.compressPdf(args: args, result: result)
            case "encryptPdf":
                self.encryptPdf(args: args, result: result)
            case "insertPages":
                self.insertPages(args: args, result: result)
            case "reorderPages":
                self.reorderPages(args: args, result: result)
            case "deletePages":
                self.deletePages(args: args, result: result)
            case "rotatePages":
                self.rotatePages(args: args, result: result)
            case "addImageToPdf":
                self.addImageToPdf(args: args, result: result)
            case "addTextToPdf":
                self.addTextToPdf(args: args, result: result)
            case "pdfToImages":
                self.pdfToImages(args: args, result: result)
            case "getPdfInfo":
                self.getPdfInfo(args: args, result: result)
            case "flattenAnnotations":
                self.flattenAnnotations(args: args, result: result)
            case "applyAnnotations":
                self.applyAnnotations(args: args, result: result)
            case "extractPdfContent":
                self.extractPdfContent(args: args, result: result)
            case "editPdfText":
                self.editPdfText(args: args, result: result)
            case "getFormFields":
                self.getFormFields(args: args, result: result)
            case "fillFormFields":
                self.fillFormFields(args: args, result: result)
            case "addOcrTextLayer":
                self.addOcrTextLayer(args: args, result: result)
            default:
                DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
            }
        }
    }

    // MARK: - Merge PDFs

    private func mergePdfs(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPaths = args["pdfPaths"] as? [String],
              let outputName = args["outputName"] as? String,
              let outputDir = args["outputDir"] as? String else {
            returnError("MERGE_ERROR", "Missing arguments", result)
            return
        }

        let mergedDocument = PDFDocument()

        for path in pdfPaths {
            guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
                returnError("MERGE_ERROR", "Could not open \((path as NSString).lastPathComponent)", result)
                return
            }
            for i in 0..<document.pageCount {
                if let page = document.page(at: i) {
                    mergedDocument.insert(page, at: mergedDocument.pageCount)
                }
            }
        }

        write(mergedDocument, to: "\(outputDir)/\(outputName).pdf", errorCode: "MERGE_ERROR", result: result)
    }

    // MARK: - Split PDF

    private func splitPdf(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let pageNumbers = args["pageNumbers"] as? [Int],
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("SPLIT_ERROR", "Invalid arguments or PDF", result)
            return
        }

        let newDocument = PDFDocument()
        for pageNum in pageNumbers.sorted() {
            if pageNum >= 0 && pageNum < document.pageCount {
                if let page = document.page(at: pageNum) {
                    newDocument.insert(page, at: newDocument.pageCount)
                }
            }
        }

        let outputPath = outputPath(outputDir, "split")
        if newDocument.write(to: URL(fileURLWithPath: outputPath)) {
            returnSuccess([outputPath], result)
        } else {
            returnError("SPLIT_ERROR", "Failed to write split PDF", result)
        }
    }

    // MARK: - Compress PDF

    /// PDFKit re-encodes embedded images as JPEG and, for the stronger presets,
    /// downsamples them to screen resolution. Text and vector content are kept.
    /// The original is returned unchanged if compression wouldn't make it smaller.
    private func compressPdf(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("COMPRESS_ERROR", "Invalid arguments", result)
            return
        }
        let dpi = args["dpi"] as? Int ?? 150

        let outputPath = outputPath(outputDir, "compressed")
        let outputUrl = URL(fileURLWithPath: outputPath)
        var options: [PDFDocumentWriteOption: Any] = [:]
        if #available(iOS 16.4, macOS 13.4, *) {
            options[.saveImagesAsJPEGOption] = true
            // "Low compression" (300 dpi) keeps full-resolution images.
            if dpi < 300 { options[.optimizeImagesForScreenOption] = true }
        }

        guard document.write(to: outputUrl, withOptions: options) else {
            returnError("COMPRESS_ERROR", "Failed to compress PDF", result)
            return
        }
        let originalSize = (try? FileManager.default.attributesOfItem(atPath: pdfPath)[.size] as? Int) ?? 0
        let newSize = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int) ?? 0
        if newSize >= originalSize, originalSize > 0 {
            try? FileManager.default.removeItem(at: outputUrl)
            try? FileManager.default.copyItem(atPath: pdfPath, toPath: outputPath)
        }
        returnSuccess(outputPath, result)
    }

    // MARK: - Encrypt PDF

    private func encryptPdf(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let password = args["password"] as? String, !password.isEmpty,
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("ENCRYPT_ERROR", "Invalid arguments", result)
            return
        }

        let allowPrinting = args["allowPrinting"] as? Bool ?? true
        let allowCopying = args["allowCopying"] as? Bool ?? false
        let allowEditing = args["allowEditing"] as? Bool ?? false

        // PDFAccessPermissions is imported as a plain enum, so combine the bit flags by hand.
        // Screen readers are always allowed, so protected files stay accessible.
        func bits(_ flags: PDFAccessPermissions...) -> UInt { flags.reduce(0) { $0 | $1.rawValue } }
        var permissions = bits(.allowsContentAccessibility)
        if allowPrinting { permissions |= bits(.allowsLowQualityPrinting, .allowsHighQualityPrinting) }
        if allowCopying { permissions |= bits(.allowsContentCopying) }
        if allowEditing {
            permissions |= bits(.allowsDocumentChanges, .allowsDocumentAssembly, .allowsCommenting, .allowsFormFieldEntry)
        }

        // A distinct, random owner password: if it equalled the user password, anyone
        // who can open the file would get owner rights and the permissions would be moot.
        let options: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: password,
            .ownerPasswordOption: UUID().uuidString,
            .accessPermissionsOption: NSNumber(value: permissions),
        ]

        let outputPath = outputPath(outputDir, "protected")
        if document.write(to: URL(fileURLWithPath: outputPath), withOptions: options) {
            returnSuccess(outputPath, result)
        } else {
            returnError("ENCRYPT_ERROR", "Failed to encrypt PDF", result)
        }
    }

    // MARK: - Edit PDF Text

    /// Locates each original string on the page, covers it with a white box and
    /// draws the replacement in the original font and size where the system has
    /// it (falling back to Helvetica). PDFKit can't rewrite content streams, so
    /// the original glyphs remain beneath the cover in the file.
    private func editPdfText(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let pageIndex = args["pageIndex"] as? Int,
              let replacements = args["replacements"] as? [String: String],
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)),
              let page = document.page(at: pageIndex) else {
            returnError("EDIT_ERROR", "Invalid arguments", result)
            return
        }
        let formatting = args["formatting"] as? [String: [String: Any]] ?? [:]

        struct Edit { let bounds: CGRect; let text: String; let font: CTFont }
        var edits: [Edit] = []

        for (old, new) in replacements where !old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && old != new {
            let oldLines = old.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let newLines = new.components(separatedBy: "\n")
            let style = formatting[old]

            for (lineIndex, oldLine) in oldLines.enumerated() {
                let matches = document.findString(oldLine, withOptions: [])
                    .flatMap { $0.selectionsByLine() }
                    .filter { $0.pages.contains(page) }
                guard let match = matches.first else {
                    returnError("EDIT_ERROR", "Couldn't find \"\(oldLine)\" on this page", result)
                    return
                }
                // Spread the new lines over the old ones; any extra new lines join the last.
                let replacement = lineIndex < oldLines.count - 1
                    ? (lineIndex < newLines.count ? newLines[lineIndex] : "")
                    : newLines.dropFirst(lineIndex).joined(separator: " ")
                let bounds = match.bounds(for: page)
                edits.append(Edit(bounds: bounds, text: replacement, font: font(matching: match, bounds: bounds, style: style)))
            }
        }

        let replaced = rerender(page: page) { ctx in
            for edit in edits {
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(edit.bounds.insetBy(dx: -1, dy: -1))
                let descent = CTFontGetDescent(edit.font)
                drawText(ctx, edit.text, font: edit.font, color: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                         at: CGPoint(x: edit.bounds.minX, y: edit.bounds.minY + descent))
            }
        }
        guard let newPage = replaced else {
            returnError("EDIT_ERROR", "Failed to render edited page", result)
            return
        }
        replacePage(at: pageIndex, in: document, with: newPage)
        write(document, to: outputPath(outputDir, "edited"), errorCode: "EDIT_ERROR", result: result)
    }

    /// The font the selection was drawn in (as reported by PDFKit), adjusted for
    /// any bold/italic the user asked for. Falls back to Helvetica at a size
    /// derived from the selection height.
    private func font(matching selection: PDFSelection, bounds: CGRect, style: [String: Any]?) -> CTFont {
        var name = "Helvetica"
        var size = max(4, bounds.height * 0.8)
        if let attributed = selection.attributedString, attributed.length > 0,
           let platformFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont {
            name = platformFont.fontName
            size = platformFont.pointSize
        }
        var font = CTFontCreateWithName(name as CFString, size, nil)
        var traits: CTFontSymbolicTraits = []
        if style?["bold"] as? Bool == true { traits.insert(.traitBold) }
        if style?["italic"] as? Bool == true { traits.insert(.traitItalic) }
        if !traits.isEmpty, let styled = CTFontCreateCopyWithSymbolicTraits(font, size, nil, traits, traits) {
            font = styled
        }
        return font
    }

    // MARK: - Insert Pages

    /// `pagePaths` may be PDFs (all pages inserted) or images (one A4 page each).
    private func insertPages(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let insertAtIndex = args["insertAtIndex"] as? Int,
              let pagePaths = args["pagePaths"] as? [String],
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("INSERT_ERROR", "Invalid arguments", result)
            return
        }

        var currentIndex = max(0, min(insertAtIndex, document.pageCount))

        for path in pagePaths {
            if path.lowercased().hasSuffix(".pdf") {
                guard let sourceDoc = PDFDocument(url: URL(fileURLWithPath: path)) else { continue }
                for i in 0..<sourceDoc.pageCount {
                    if let page = sourceDoc.page(at: i) {
                        document.insert(page, at: currentIndex)
                        currentIndex += 1
                    }
                }
            } else if let image = loadImage(path: path), let page = imagePage(image) {
                document.insert(page, at: currentIndex)
                currentIndex += 1
            }
        }

        write(document, to: outputPath(outputDir, "inserted"), errorCode: "INSERT_ERROR", result: result)
    }

    // MARK: - Reorder Pages

    private func reorderPages(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let newOrder = args["newOrder"] as? [Int],
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("REORDER_ERROR", "Invalid arguments", result)
            return
        }

        // Reorder within the same document so outline and metadata survive.
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }
        for _ in pages { document.removePage(at: 0) }
        for index in newOrder where index >= 0 && index < pages.count {
            document.insert(pages[index], at: document.pageCount)
        }

        write(document, to: outputPath(outputDir, "reordered"), errorCode: "REORDER_ERROR", result: result)
    }

    // MARK: - Delete Pages

    private func deletePages(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let pageIndices = args["pageIndices"] as? [Int],
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("DELETE_ERROR", "Invalid arguments", result)
            return
        }

        for index in Set(pageIndices).sorted().reversed() {
            if index >= 0 && index < document.pageCount {
                document.removePage(at: index)
            }
        }

        write(document, to: outputPath(outputDir, "trimmed"), errorCode: "DELETE_ERROR", result: result)
    }

    // MARK: - Rotate Pages

    private func rotatePages(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let pageIndices = args["pageIndices"] as? [Int],
              let degrees = args["degrees"] as? Int,
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("ROTATE_ERROR", "Invalid arguments", result)
            return
        }

        for index in pageIndices {
            if index >= 0 && index < document.pageCount {
                if let page = document.page(at: index) {
                    page.rotation = ((page.rotation + degrees) % 360 + 360) % 360
                }
            }
        }

        write(document, to: outputPath(outputDir, "rotated"), errorCode: "ROTATE_ERROR", result: result)
    }

    // MARK: - Add Image to PDF

    private func addImageToPdf(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let pageIndex = args["pageIndex"] as? Int,
              let imageBytes = args["imageBytes"] as? FlutterStandardTypedData,
              let x = args["x"] as? Double,
              let y = args["y"] as? Double,
              let width = args["width"] as? Double,
              let height = args["height"] as? Double,
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)),
              let page = document.page(at: pageIndex),
              let image = loadImage(data: imageBytes.data) else {
            returnError("ADD_IMAGE_ERROR", "Invalid arguments", result)
            return
        }

        // Same convention as Android: (x, y) from the media box's top-left corner.
        let mediaBox = page.bounds(for: .mediaBox)
        let rect = CGRect(x: x, y: Double(mediaBox.height) - y - height, width: width, height: height)
        guard let newPage = rerender(page: page, overlay: { ctx in ctx.draw(image, in: rect) }) else {
            returnError("ADD_IMAGE_ERROR", "Failed to render signed page", result)
            return
        }
        replacePage(at: pageIndex, in: document, with: newPage)
        write(document, to: outputPath(outputDir, "signed"), errorCode: "ADD_IMAGE_ERROR", result: result)
    }

    // MARK: - Add Text to PDF

    private func addTextToPdf(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let pageIndex = args["pageIndex"] as? Int,
              let text = args["text"] as? String,
              let x = args["x"] as? Double,
              let y = args["y"] as? Double,
              let fontSize = args["fontSize"] as? Double,
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)),
              let page = document.page(at: pageIndex) else {
            returnError("ADD_TEXT_ERROR", "Invalid arguments", result)
            return
        }

        let mediaBox = page.bounds(for: .mediaBox)
        let font = CTFontCreateWithName("Helvetica" as CFString, CGFloat(fontSize), nil)
        let newPage = rerender(page: page) { ctx in
            self.drawText(ctx, text, font: font, color: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                          at: CGPoint(x: x, y: Double(mediaBox.height) - y))
        }
        guard let newPage = newPage else {
            returnError("ADD_TEXT_ERROR", "Failed to render page", result)
            return
        }
        replacePage(at: pageIndex, in: document, with: newPage)
        write(document, to: outputPath(outputDir, "text"), errorCode: "ADD_TEXT_ERROR", result: result)
    }

    // MARK: - Form Fields

    private func widgets(in document: PDFDocument) -> [(page: Int, annotation: PDFAnnotation)] {
        var widgets: [(Int, PDFAnnotation)] = []
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for annotation in page.annotations where annotation.type == "Widget" {
                guard let name = annotation.fieldName, !name.isEmpty else { continue }
                if annotation.widgetFieldType == .button && annotation.widgetControlType == .pushButtonControl { continue }
                widgets.append((i, annotation))
            }
        }
        return widgets
    }

    private func getFormFields(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("FORM_ERROR", "Invalid PDF", result)
            return
        }

        // Radio groups have one widget per option; report each field once.
        var order: [String] = []
        var grouped: [String: [(page: Int, annotation: PDFAnnotation)]] = [:]
        for widget in widgets(in: document) {
            let name = widget.annotation.fieldName!
            if grouped[name] == nil { order.append(name) }
            grouped[name, default: []].append(widget)
        }

        let fields: [[String: Any]] = order.map { name in
            let group = grouped[name]!
            let first = group[0].annotation
            var type = "text"
            var value = first.widgetStringValue ?? ""
            var options: [String] = []
            switch first.widgetFieldType {
            case .button:
                let states = group.compactMap { $0.annotation.buttonWidgetStateString }
                if first.widgetControlType == .radioButtonControl {
                    type = "radio"
                    options = states
                    value = group.first { $0.annotation.buttonWidgetState == .onState }?.annotation.buttonWidgetStateString ?? ""
                } else {
                    type = "checkbox"
                    options = Array(states.prefix(1))
                    value = first.buttonWidgetState == .onState ? "true" : "false"
                }
            case .choice:
                type = first.isListChoice ? "list" : "dropdown"
                options = first.choices ?? []
            case .signature:
                type = "signature"
            default:
                break
            }
            return ["name": name, "type": type, "value": value, "page": group[0].page, "options": options]
        }
        returnSuccess(fields, result)
    }

    private func fillFormFields(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let fieldValues = args["fieldValues"] as? [String: String],
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("FORM_ERROR", "Invalid arguments", result)
            return
        }

        let all = widgets(in: document)
        if all.isEmpty {
            returnError("FORM_ERROR", "This PDF has no fillable form fields", result)
            return
        }
        let truthy: Set<String> = ["true", "yes", "on", "1", "x", "checked"]
        for (_, annotation) in all {
            guard let name = annotation.fieldName, let value = fieldValues[name] else { continue }
            switch annotation.widgetFieldType {
            case .button where annotation.widgetControlType == .radioButtonControl:
                annotation.buttonWidgetState = annotation.buttonWidgetStateString == value ? .onState : .offState
            case .button:
                let on = truthy.contains(value.lowercased()) || value == annotation.buttonWidgetStateString
                annotation.buttonWidgetState = on ? .onState : .offState
            case .signature:
                break // Signatures are placed as images via addImageToPdf.
            default:
                annotation.widgetStringValue = value
            }
        }

        write(document, to: outputPath(outputDir, "filled"), errorCode: "FORM_ERROR", result: result)
    }

    // MARK: - Annotations

    /// Adds annotations drawn in the Flutter overlay as standard PDF annotations
    /// (highlight, underline, strike-out, ink, free text, note), which every PDF
    /// viewer can display and which stay editable. Coordinates arrive normalised
    /// (0–1) relative to the page as displayed (top-left origin, rotation applied).
    private func applyAnnotations(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let annotations = args["annotations"] as? [[String: Any]],
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("ANNOTATION_ERROR", "Invalid arguments", result)
            return
        }

        for item in annotations {
            guard let pageIndex = (item["pageIndex"] as? NSNumber)?.intValue,
                  let page = document.page(at: pageIndex),
                  let type = item["type"] as? String else { continue }
            let mapper = DisplayMapper(page: page)
            let color = argbColor((item["color"] as? NSNumber)?.int64Value ?? 0xFFFFEB3B)
            let rect = (item["rect"] as? [String: Any]).flatMap { normalizedRect($0) }
            let text = item["text"] as? String

            switch type {
            case "highlight", "underline", "strikethrough":
                guard let r = rect else { continue }
                let bounds = mapper.map(r)
                let subtype: PDFAnnotationSubtype = type == "highlight" ? .highlight : (type == "underline" ? .underline : .strikeOut)
                let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
                annotation.color = type == "highlight" ? color.withAlphaComponent(0.4) : color
                // Quad points are relative to the annotation's origin: TL, TR, BL, BR.
                annotation.quadrilateralPoints = [
                    CGPoint(x: 0, y: bounds.height), CGPoint(x: bounds.width, y: bounds.height),
                    CGPoint(x: 0, y: 0), CGPoint(x: bounds.width, y: 0),
                ].map { NSValue(point: $0) }
                page.addAnnotation(annotation)
            case "freehand":
                let points = (item["points"] as? [[String: Any]] ?? []).compactMap { p -> CGPoint? in
                    guard let x = (p["x"] as? NSNumber)?.doubleValue, let y = (p["y"] as? NSNumber)?.doubleValue else { return nil }
                    return mapper.map(x: x, y: y)
                }
                guard points.count > 1 else { continue }
                let box = mapper.box
                let path = PlatformBezierPath()
                path.move(to: CGPoint(x: points[0].x - box.minX, y: points[0].y - box.minY))
                for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x - box.minX, y: point.y - box.minY)) }
                let annotation = PDFAnnotation(bounds: box, forType: .ink, withProperties: nil)
                annotation.color = color
                let border = PDFBorder()
                // strokeWidth is in logical pixels of the on-screen page; normalise by its width.
                let strokeWidth = (item["strokeWidth"] as? NSNumber)?.doubleValue ?? 2
                let viewWidth = (item["viewWidth"] as? NSNumber)?.doubleValue ?? 360
                border.lineWidth = CGFloat(strokeWidth) * mapper.displaySize.width / CGFloat(viewWidth)
                annotation.border = border
                annotation.add(path)
                page.addAnnotation(annotation)
            case "textNote":
                guard let r = rect, let text = text, !text.isEmpty else { continue }
                let origin = mapper.map(x: r.minX, y: r.minY)
                let font = PlatformFont(name: "Helvetica", size: 12) ?? PlatformFont.systemFont(ofSize: 12)
                let lines = text.components(separatedBy: "\n")
                let width = lines.map { CGFloat($0.count) * 7 }.max() ?? 100
                let height = CGFloat(lines.count) * 15 + 4
                let annotation = PDFAnnotation(bounds: CGRect(x: origin.x, y: origin.y - height, width: width + 8, height: height),
                                               forType: .freeText, withProperties: nil)
                annotation.contents = text
                annotation.font = font
                annotation.fontColor = color
                annotation.color = .clear
                page.addAnnotation(annotation)
            case "stickyNote":
                guard let r = rect else { continue }
                let origin = mapper.map(x: r.minX, y: r.minY)
                let annotation = PDFAnnotation(bounds: CGRect(x: origin.x, y: origin.y - 20, width: 20, height: 20),
                                               forType: .text, withProperties: nil)
                annotation.contents = text ?? ""
                annotation.color = color
                annotation.iconType = .note
                page.addAnnotation(annotation)
            default:
                continue
            }
        }

        write(document, to: outputPath(outputDir, "annotated"), errorCode: "ANNOTATION_ERROR", result: result)
    }

    private func normalizedRect(_ map: [String: Any]) -> CGRect? {
        guard let x = (map["x"] as? NSNumber)?.doubleValue,
              let y = (map["y"] as? NSNumber)?.doubleValue,
              let w = (map["width"] as? NSNumber)?.doubleValue,
              let h = (map["height"] as? NSNumber)?.doubleValue else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func argbColor(_ argb: Int64) -> PlatformColor {
        PlatformColor(red: CGFloat((argb >> 16) & 0xFF) / 255,
                      green: CGFloat((argb >> 8) & 0xFF) / 255,
                      blue: CGFloat(argb & 0xFF) / 255,
                      alpha: 1)
    }

    /// Maps display coordinates (top-left origin, rotation applied) to PDF page space.
    struct DisplayMapper {
        let box: CGRect
        let rotation: Int

        init(page: PDFPage) {
            box = page.bounds(for: .cropBox)
            rotation = ((page.rotation % 360) + 360) % 360
        }

        var displaySize: CGSize {
            rotation == 90 || rotation == 270 ? CGSize(width: box.height, height: box.width) : box.size
        }

        /// Normalised display point → page space.
        func map(x nx: Double, y ny: Double) -> CGPoint {
            let dx = CGFloat(nx) * displaySize.width
            let dy = CGFloat(ny) * displaySize.height
            let u: CGFloat, v: CGFloat
            switch rotation {
            case 90: (u, v) = (dy, dx)
            case 180: (u, v) = (box.width - dx, dy)
            case 270: (u, v) = (box.width - dy, box.height - dx)
            default: (u, v) = (dx, box.height - dy)
            }
            return CGPoint(x: box.minX + u, y: box.minY + v)
        }

        /// Normalised display rect → axis-aligned page-space rect.
        func map(_ rect: CGRect) -> CGRect {
            let a = map(x: Double(rect.minX), y: Double(rect.minY))
            let b = map(x: Double(rect.maxX), y: Double(rect.maxY))
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        }

        /// Angle (radians) that makes text run left-to-right as displayed.
        var textAngle: CGFloat { CGFloat(rotation) * .pi / 180 }
    }

    // MARK: - OCR Text Layer

    /// Adds an invisible, selectable text layer from OCR results so scanned pages
    /// become searchable. Line boxes arrive in pixel coordinates of the rendered
    /// page image (top-left origin, rotation applied); each line is stretched to
    /// span its box so selection highlights line up with the image.
    private func addOcrTextLayer(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let pages = args["pages"] as? [[String: Any]],
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("OCR_LAYER_ERROR", "Invalid arguments", result)
            return
        }

        for pageData in pages {
            guard let pageIndex = (pageData["pageIndex"] as? NSNumber)?.intValue,
                  let page = document.page(at: pageIndex),
                  let imageWidth = (pageData["imageWidth"] as? NSNumber)?.doubleValue, imageWidth > 0,
                  let imageHeight = (pageData["imageHeight"] as? NSNumber)?.doubleValue, imageHeight > 0,
                  let lines = pageData["lines"] as? [[String: Any]], !lines.isEmpty else { continue }
            let mapper = DisplayMapper(page: page)

            let newPage = rerender(page: page) { ctx in
                for line in lines {
                    guard let text = (line["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                          let left = (line["left"] as? NSNumber)?.doubleValue,
                          let top = (line["top"] as? NSNumber)?.doubleValue,
                          let width = (line["width"] as? NSNumber)?.doubleValue,
                          let height = (line["height"] as? NSNumber)?.doubleValue else { continue }
                    let heightPt = CGFloat(height / imageHeight) * mapper.displaySize.height
                    let widthPt = CGFloat(width / imageWidth) * mapper.displaySize.width
                    let font = CTFontCreateWithName("Helvetica" as CFString, max(1, heightPt * 0.85), nil)
                    let natural = self.lineWidth(text, font: font)
                    // Baseline sits ~20% of the box height above the box bottom.
                    let baseline = mapper.map(x: left / imageWidth, y: (top + height * 0.8) / imageHeight)
                    self.drawText(ctx, text, font: font, color: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  at: baseline, horizontalScale: natural > 0 ? widthPt / natural : 1,
                                  angle: mapper.textAngle, invisible: true)
                }
            }
            if let newPage = newPage { replacePage(at: pageIndex, in: document, with: newPage) }
        }

        write(document, to: outputPath(outputDir, "searchable"), errorCode: "OCR_LAYER_ERROR", result: result)
    }

    // MARK: - PDF to Images

    private func pdfToImages(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let format = args["format"] as? String,
              let dpi = args["dpi"] as? Int,
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("PDF_TO_IMAGES_ERROR", "Invalid arguments", result)
            return
        }
        if document.isLocked {
            returnError("PDF_TO_IMAGES_ERROR", "This PDF is password protected", result)
            return
        }

        var imagePaths: [String] = []
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let ext = (format == "jpg" || format == "jpeg") ? "jpg" : "png"

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let mapper = DisplayMapper(page: page)
            var scale = CGFloat(dpi) / 72.0
            // Cap at ~24 MP per page so a large-format page can't exhaust memory.
            let pixels = mapper.displaySize.width * scale * mapper.displaySize.height * scale
            if pixels > 24_000_000 { scale *= sqrt(24_000_000 / pixels) }
            let width = max(1, Int(mapper.displaySize.width * scale))
            let height = max(1, Int(mapper.displaySize.height * scale))

            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.interpolationQuality = .high
            ctx.scaleBy(x: scale, y: scale)
            // PDFKit applies the page's rotation and crop box for us.
            page.draw(with: .cropBox, to: ctx)
            guard let cgImage = ctx.makeImage() else { continue }

            let imagePath = "\(outputDir)/page_\(stamp)_\(i + 1).\(ext)"
            if writeImage(cgImage, to: imagePath, jpeg: ext == "jpg") {
                imagePaths.append(imagePath)
            }
        }

        returnSuccess(imagePaths, result)
    }

    // MARK: - Get PDF Info

    private func getPdfInfo(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("INFO_ERROR", "Invalid PDF", result)
            return
        }
        // Match Android (PDFBox refuses to open it): a password-protected PDF
        // can't be inspected without the password.
        if document.isLocked {
            returnError("INFO_ERROR", "This PDF is password protected", result)
            return
        }

        let info: [String: Any] = [
            "pageCount": document.pageCount,
            "title": document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? "",
            "author": document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String ?? "",
            "isEncrypted": document.isEncrypted
        ]

        returnSuccess(info, result)
    }

    // MARK: - Flatten Annotations

    /// Burns annotation appearances into page content so markup can no longer be
    /// edited or hidden.
    private func flattenAnnotations(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let outputDir = args["outputDir"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("FLATTEN_ERROR", "Invalid arguments", result)
            return
        }

        var options: [PDFDocumentWriteOption: Any] = [:]
        if #available(iOS 16.0, macOS 13.0, *) {
            options[.burnInAnnotationsOption] = true
        }
        let outputPath = outputPath(outputDir, "flattened")
        if document.write(to: URL(fileURLWithPath: outputPath), withOptions: options) {
            returnSuccess(outputPath, result)
        } else {
            returnError("FLATTEN_ERROR", "Failed to flatten", result)
        }
    }

    // MARK: - Extract PDF Content

    private func extractPdfContent(args: [String: Any], result: @escaping FlutterResult) {
        guard let pdfPath = args["pdfPath"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            returnError("EXTRACT_ERROR", "Invalid PDF", result)
            return
        }

        var pages: [[String: Any]] = []
        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                let text = page.string ?? ""
                pages.append(["text": text, "pageIndex": i])
            }
        }

        returnSuccess(["pages": pages], result)
    }

    // MARK: - Page re-rendering

    /// Replays `page` into a fresh one-page PDF with `overlay` drawn on top, in the
    /// page's own (unrotated) coordinate space. Returns the new page with the
    /// original crop box, rotation and annotations (links, form widgets, notes).
    private func rerender(page: PDFPage, overlay: (CGContext) -> Void) -> PDFPage? {
        guard let pageRef = page.pageRef else { return nil }
        var mediaBox = page.bounds(for: .mediaBox)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        ctx.beginPDFPage([kCGPDFContextMediaBox as String: Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)] as CFDictionary)
        ctx.drawPDFPage(pageRef)
        ctx.saveGState()
        overlay(ctx)
        ctx.restoreGState()
        ctx.endPDFPage()
        ctx.closePDF()

        guard let newPage = PDFDocument(data: data as Data)?.page(at: 0) else { return nil }
        newPage.setBounds(page.bounds(for: .cropBox), for: .cropBox)
        newPage.rotation = page.rotation
        for annotation in page.annotations {
            page.removeAnnotation(annotation)
            newPage.addAnnotation(annotation)
        }
        return newPage
    }

    private func replacePage(at index: Int, in document: PDFDocument, with page: PDFPage) {
        document.removePage(at: index)
        document.insert(page, at: index)
    }

    private func drawText(_ ctx: CGContext, _ text: String, font: CTFont, color: CGColor, at point: CGPoint,
                          horizontalScale: CGFloat = 1, angle: CGFloat = 0, invisible: Bool = false) {
        // CoreText falls back to other system fonts for glyphs Helvetica lacks (CJK, Devanagari, ...).
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.saveGState()
        ctx.translateBy(x: point.x, y: point.y)
        ctx.rotate(by: angle)
        ctx.scaleBy(x: horizontalScale, y: 1)
        ctx.textMatrix = .identity
        ctx.textPosition = .zero
        if invisible { ctx.setTextDrawingMode(.invisible) }
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private func lineWidth(_ text: String, font: CTFont) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil))
    }

    // MARK: - Image helpers

    private func loadImage(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // Honour EXIF orientation (camera photos) by asking ImageIO for a transformed thumbnail.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 6000,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func loadImage(path: String) -> CGImage? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return loadImage(data: data)
    }

    /// One A4 page with the image fitted and centred.
    private func imagePage(_ image: CGImage) -> PDFPage? {
        var a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &a4, nil) else { return nil }
        let scale = min(a4.width / CGFloat(image.width), a4.height / CGFloat(image.height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        ctx.beginPDFPage(nil)
        ctx.draw(image, in: CGRect(x: (a4.width - w) / 2, y: (a4.height - h) / 2, width: w, height: h))
        ctx.endPDFPage()
        ctx.closePDF()
        return PDFDocument(data: data as Data)?.page(at: 0)
    }

    private func writeImage(_ image: CGImage, to path: String, jpeg: Bool) -> Bool {
        let type = (jpeg ? "public.jpeg" : "public.png") as CFString
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, type, 1, nil) else { return false }
        let properties: [CFString: Any] = jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.9] : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    // MARK: - Helpers

    private func outputPath(_ outputDir: String, _ prefix: String) -> String {
        "\(outputDir)/\(prefix)_\(Int(Date().timeIntervalSince1970 * 1000)).pdf"
    }

    private func write(_ document: PDFDocument, to path: String, errorCode: String, result: @escaping FlutterResult) {
        if document.write(to: URL(fileURLWithPath: path)) {
            returnSuccess(path, result)
        } else {
            returnError(errorCode, "Failed to write PDF", result)
        }
    }

    private func returnSuccess(_ value: Any, _ result: @escaping FlutterResult) {
        DispatchQueue.main.async { result(value) }
    }

    private func returnError(_ code: String, _ message: String, _ result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            result(FlutterError(code: code, message: message, details: nil))
        }
    }
}
