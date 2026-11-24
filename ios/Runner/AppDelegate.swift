import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
    // Handlers are held for the app's lifetime; channels keep only weak-ish closures.
    private let pdfHandler = PdfHandler()
    private let ocrHandler = TesseractOcrHandler()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Google Mobile Ads is initialised from Dart (AdService.initialize).
        // Channels are registered through the plugin registry rather than by casting
        // window.rootViewController, which isn't guaranteed to exist at this point.
        if let registrar = self.registrar(forPlugin: "DocuScanProChannels") {
            let messenger = registrar.messenger()

            // PDF channel
            let pdfChannel = FlutterMethodChannel(name: "com.docuscanpro.app/pdf", binaryMessenger: messenger)
            pdfChannel.setMethodCallHandler(pdfHandler.handle)

            // OCR channel (Tesseract)
            let ocrChannel = FlutterMethodChannel(name: "com.docuscanpro.app/ocr", binaryMessenger: messenger)
            ocrChannel.setMethodCallHandler(ocrHandler.handle)

            // Conversion channel
            let conversionChannel = FlutterMethodChannel(name: "com.docuscanpro.app/conversion", binaryMessenger: messenger)
            let pdfHandler = self.pdfHandler
            conversionChannel.setMethodCallHandler { call, result in
                switch call.method {
                case "extractPdfContent":
                    pdfHandler.handle(call, result: result)
                case "cloudConvert":
                    CloudConversionHandler.convert(call: call, result: result)
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
