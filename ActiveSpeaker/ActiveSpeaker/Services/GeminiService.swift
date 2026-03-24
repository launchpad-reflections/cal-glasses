import UIKit

/// Direct Gemini API client for food analysis.
/// Sends images + transcript and receives structured food data.
final class GeminiService {

    private let apiKey: String
    private let model = "gemini-2.0-flash"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Analyze food images + transcript, returning structured food items.
    func analyzeFoodImages(images: [UIImage], transcript: String) async throws -> FoodAnalysisResult {
        let url = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(apiKey)")!

        // Build multimodal content parts
        var parts: [[String: Any]] = []

        // Add the system prompt as text
        parts.append(["text": Self.systemPrompt(transcript: transcript)])

        // Add images as base64
        for (i, image) in images.enumerated() {
            guard let jpegData = image.jpegData(compressionQuality: 0.8) else { continue }
            let base64 = jpegData.base64EncodedString()
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": base64
                ]
            ])
            NSLog("[Gemini] added image \(i+1)/\(images.count) (\(jpegData.count / 1024)KB)")
        }

        let body: [String: Any] = [
            "contents": [
                ["parts": parts]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "responseMimeType": "application/json"
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        NSLog("[Gemini] sending request with \(images.count) images + transcript (\(transcript.count) chars)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            NSLog("[Gemini] API error \(httpResponse.statusCode): \(errorBody.prefix(500))")
            throw GeminiError.apiError(httpResponse.statusCode, errorBody)
        }

        // Parse Gemini response structure
        let geminiResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = geminiResponse?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let responseParts = content["parts"] as? [[String: Any]],
              let text = responseParts.first?["text"] as? String else {
            NSLog("[Gemini] unexpected response structure")
            throw GeminiError.parseError("Unexpected response structure")
        }

        NSLog("[Gemini] response text: \(text.prefix(500))")

        // Parse the JSON from Gemini's response
        guard let jsonData = text.data(using: .utf8) else {
            throw GeminiError.parseError("Could not convert response to data")
        }

        let result = try JSONDecoder().decode(FoodAnalysisResult.self, from: jsonData)
        NSLog("[Gemini] parsed \(result.items.count) food items")
        return result
    }

    // MARK: - Prompt

    private static func systemPrompt(transcript: String) -> String {
        """
        You are a food analysis AI for a calorie tracking app. You receive images from a 30-second recording \
        of someone's meal, captured through smart glasses, along with a transcript of what they said.

        Your job:
        1. Identify ALL food and drink items visible in the images
        2. Cross-reference with the transcript — if the user says quantities (e.g., "I had 30 chips", \
        "half a plate", "two glasses of water"), use those to determine amounts
        3. For each item, determine:
           - Whether a nutrition label is visible (if so, prefer that data)
           - Whether it's packaged food, a prepared dish, or a drink
           - A reasonable quantity estimate
           - Your confidence level (0.0 to 1.0)
        4. For water/drinks mentioned verbally but not shown, still include them
        5. Do NOT duplicate items — if the same food appears in multiple images, count it once

        The user's transcript during the recording:
        \"\(transcript)\"

        Respond with ONLY valid JSON matching this exact schema:
        {
          "items": [
            {
              "name": "string (food/drink name)",
              "type": "packaged | dish | drink",
              "quantity": "string (human-readable, e.g. '2 servings', '1 plate', '500ml')",
              "quantity_ml": number or null (for drinks only, in milliliters),
              "has_nutrition_label": boolean,
              "needs_manual_entry": boolean (true if uncertain or no label),
              "confidence": number (0.0 to 1.0)
            }
          ]
        }

        If no food is detected, return {"items": []}.
        """
    }

    enum GeminiError: Error, LocalizedError {
        case invalidResponse
        case apiError(Int, String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid response from Gemini"
            case .apiError(let code, let msg): return "Gemini API error \(code): \(msg.prefix(100))"
            case .parseError(let msg): return "Parse error: \(msg)"
            }
        }
    }
}
