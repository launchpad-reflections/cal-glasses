import Foundation

/// Loads prompt text from the bundled prompts/ folder.
enum GlassesPrompt {

    /// Load a prompt by filename (without extension).
    static func load(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md",
                                        subdirectory: "prompts") else {
            // Fallback: try without subdirectory (flat bundle)
            guard let url = Bundle.main.url(forResource: name, withExtension: "md") else {
                NSLog("[GlassesPrompt] Could not find \(name).md in bundle")
                return nil
            }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// The default startup prompt.
    static var defaultPrompt: String {
        load("startup") ?? fallbackText
    }

    private static let fallbackText = """
    Pick your archetype and optimize to do the best in it. \
    CEO? Need to know how to move people, money, and a technical vision. \
    CMO? Need to have 100,000 on social media. \
    CTO? Need deep technical experience, not vibes: BAIR, papers, hardware, niches. \
    I've identified mine: CEO. Now optimize for getting to places where you want to be.
    """
}
