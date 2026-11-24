import Flutter
import SwiftyTesseract
import UIKit

/// Handles Tesseract OCR for extended languages on iOS (SwiftyTesseract /
/// libtesseract). ML Kit handles the primary 5 script families on the Dart side.
class TesseractOcrHandler: NSObject {

    private lazy var tessDataDir: URL = {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = documentsDir.appendingPathComponent("tessdata")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Points SwiftyTesseract at the downloaded packs instead of the app bundle.
    private struct DownloadedLanguages: LanguageModelDataSource {
        let pathToTrainedData: String
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // getAvailableLanguages takes no arguments, so don't require a map here;
        // each method validates the arguments it needs.
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "recognizeText":
            recognizeText(args: args, result: result)
        case "downloadLanguagePack":
            downloadLanguagePack(args: args, result: result)
        case "getAvailableLanguages":
            getAvailableLanguages(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func recognizeText(args: [String: Any], result: @escaping FlutterResult) {
        guard let imagePath = args["imagePath"] as? String,
              let languageCode = args["languageCode"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }

        let langFile = tessDataDir.appendingPathComponent("\(languageCode).traineddata")
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: langFile.path)[.size] as? Int) ?? 0
        // SwiftyTesseract calls fatalError if initialisation fails, so never hand it a missing or empty pack.
        guard fileSize > 0 else {
            result(FlutterError(
                code: "LANGUAGE_NOT_DOWNLOADED",
                message: "Language pack '\(languageCode)' is not downloaded",
                details: nil
            ))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = UIImage(contentsOfFile: imagePath) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "OCR_ERROR", message: "Could not load image", details: nil))
                }
                return
            }

            let tesseract = Tesseract(
                language: .custom(languageCode),
                dataSource: DownloadedLanguages(pathToTrainedData: self.tessDataDir.path),
                engineMode: .lstmOnly
            )

            switch tesseract.recognizedBlocks(from: image, for: .textline) {
            case .success(let (text, lines)):
                let blocks: [[String: Any]] = lines.compactMap { line in
                    let lineText = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !lineText.isEmpty else { return nil }
                    let rect = line.boundingBox.cgRect
                    return [
                        "text": lineText,
                        "confidence": Double(line.confidence),
                        "bounds": [
                            "left": rect.minX,
                            "top": rect.minY,
                            "width": rect.width,
                            "height": rect.height,
                        ],
                    ]
                }
                DispatchQueue.main.async { result(["text": text, "blocks": blocks]) }
            case .failure(let error):
                DispatchQueue.main.async {
                    result(FlutterError(code: "OCR_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    /// Downloads a pack from tessdata_fast. The file is moved into place only
    /// once complete, so an interrupted download never looks installed.
    private func downloadLanguagePack(args: [String: Any], result: @escaping FlutterResult) {
        guard let languageCode = args["languageCode"] as? String,
              languageCode.range(of: "^[a-z_]{3,12}$", options: .regularExpression) != nil else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid language code", details: nil))
            return
        }

        let destination = tessDataDir.appendingPathComponent("\(languageCode).traineddata")
        if FileManager.default.fileExists(atPath: destination.path) {
            result(true)
            return
        }

        let urlString = "https://github.com/tesseract-ocr/tessdata_fast/raw/main/\(languageCode).traineddata"
        guard let url = URL(string: urlString) else {
            result(FlutterError(code: "INVALID_URL", message: "Invalid download URL", details: nil))
            return
        }

        let task = URLSession.shared.downloadTask(with: url) { tempUrl, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DOWNLOAD_ERROR", message: error.localizedDescription, details: nil))
                }
                return
            }
            guard let tempUrl = tempUrl,
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                DispatchQueue.main.async {
                    result(FlutterError(code: "DOWNLOAD_ERROR",
                                        message: "Failed to download language pack: HTTP \(status)", details: nil))
                }
                return
            }

            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: tempUrl, to: destination)
                DispatchQueue.main.async { result(true) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DOWNLOAD_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
        task.resume()
    }

    private func getAvailableLanguages(result: @escaping FlutterResult) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: tessDataDir.path)) ?? []
        let languages = files
            .filter { $0.hasSuffix(".traineddata") }
            .map { String($0.dropLast(".traineddata".count)) }
        result(languages)
    }
}
