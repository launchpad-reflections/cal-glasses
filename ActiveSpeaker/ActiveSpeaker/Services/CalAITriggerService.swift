import Foundation

/// Triggers the Cal AI Appium automation server running on the Mac.
/// Sends an HTTP POST with the number of photos to upload.
enum CalAITriggerService {

    /// The Mac's automation server URL.
    /// Update this to your Mac's local IP if different.
    static var serverURL = "http://192.168.1.175:8765"

    /// Trigger the Cal AI upload automation on the Mac.
    /// - Parameter count: Number of photos to upload (1-3)
    static func triggerUpload(count: Int) async -> Bool {
        guard let url = URL(string: "\(serverURL)/upload") else {
            NSLog("[CalAI] Invalid server URL: \(serverURL)")
            return false
        }

        let body: [String: Int] = ["count": min(max(count, 1), 3)]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let responseStr = String(data: data, encoding: .utf8) ?? ""
                NSLog("[CalAI] Automation triggered: \(responseStr)")
                return true
            } else {
                NSLog("[CalAI] Server returned non-200 response")
                return false
            }
        } catch {
            NSLog("[CalAI] Failed to trigger automation: \(error.localizedDescription)")
            NSLog("[CalAI] Make sure server.py is running on your Mac at \(serverURL)")
            return false
        }
    }

    /// Check if the automation server is reachable.
    static func checkServer() async -> Bool {
        guard let url = URL(string: "\(serverURL)/status") else { return false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
