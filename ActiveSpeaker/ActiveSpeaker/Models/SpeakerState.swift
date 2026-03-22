import SwiftUI

enum SpeakerState {
    case speaking
    case maybe
    case silent

    var label: String {
        switch self {
        case .speaking: return "SPEAKING"
        case .maybe:    return "MAYBE"
        case .silent:   return "SILENT"
        }
    }

    var confidence: String {
        switch self {
        case .speaking: return "High"
        case .maybe:    return "Low"
        case .silent:   return ""
        }
    }

    var color: Color {
        switch self {
        case .speaking: return .green
        case .maybe:    return .orange
        case .silent:   return .red
        }
    }

    var displayText: String {
        if confidence.isEmpty {
            return label
        }
        return "\(label) (\(confidence))"
    }
}
