import Foundation

enum GlassesConnectionState: Equatable {
    case disconnected
    case registering
    case registered
    case streaming
    case error(String)

    var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .registering:  return "Connecting..."
        case .registered:   return "Connected"
        case .streaming:    return "Streaming"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
