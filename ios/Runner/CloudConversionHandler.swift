import Flutter
import Foundation

/// Handles cloud-based file conversion for complex PDF layouts.
class CloudConversionHandler {

    static func convert(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let fileContent = args["fileContent"] as? String,
              let sourceFormat = args["sourceFormat"] as? String,
              let targetFormat = args["targetFormat"] as? String,
              let baseUrl = args["baseUrl"] as? String,
              let url = URL(string: baseUrl) else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = args["apiKey"] as? String, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "file": fileContent,
            "sourceFormat": sourceFormat,
            "targetFormat": targetFormat
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            result(FlutterError(code: "ENCODE_ERROR", message: error.localizedDescription, details: nil))
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "CLOUD_CONVERSION_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
                return
            }

            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                // The server returns {"error": "..."} on failure.
                let serverMessage = data
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["error"] as? String
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "CLOUD_CONVERSION_ERROR",
                        message: serverMessage ?? "Server returned HTTP \(status)",
                        details: nil
                    ))
                }
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let content = json["content"] as? String else {
                    throw NSError(domain: "CloudConversion", code: 0,
                                  userInfo: [NSLocalizedDescriptionKey: "Unexpected server response"])
                }
                let responseMap: [String: Any] = [
                    "content": content,
                    "format": json["format"] as? String ?? targetFormat
                ]
                DispatchQueue.main.async { result(responseMap) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "PARSE_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
        task.resume()
    }
}
