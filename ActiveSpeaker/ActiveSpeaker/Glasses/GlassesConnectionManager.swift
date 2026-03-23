import Foundation
import MWDATCore
import os
import SwiftUI

/// Manages Meta glasses registration, device discovery, and connection state.
@MainActor
final class GlassesConnectionManager: ObservableObject {

    @Published private(set) var connectionState: GlassesConnectionState = .disconnected
    @Published private(set) var devices: [DeviceIdentifier] = []
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    let wearables: WearablesInterface

    private var registrationTask: Task<Void, Never>?
    private var deviceStreamTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.activespeaker", category: "GlassesConnection")

    init(wearables: WearablesInterface) {
        self.wearables = wearables
        self.devices = wearables.devices
        syncRegistrationState(wearables.registrationState)

        deviceStreamTask = Task {
            for await devices in wearables.devicesStream() {
                self.devices = devices
            }
        }

        registrationTask = Task {
            for await state in wearables.registrationStateStream() {
                self.syncRegistrationState(state)
            }
        }
    }

    deinit {
        registrationTask?.cancel()
        deviceStreamTask?.cancel()
    }

    func connect() {
        guard connectionState != .registering else { return }

        Task {
            do {
                try await wearables.startRegistration()
            } catch {
                setError(String(describing: error))
            }
        }
    }

    func disconnect() {
        guard connectionState == .registered || connectionState == .streaming else { return }

        Task {
            do {
                try await wearables.startUnregistration()
            } catch {
                setError(String(describing: error))
            }
        }
    }

    /// Handle the deep link callback from Meta AI app.
    func handleURL(_ url: URL) {
        Task {
            do {
                _ = try await Wearables.shared.handleUrl(url)
            } catch {
                setError(String(describing: error))
            }
        }
    }

    func dismissError() {
        showError = false
    }

    // MARK: - Private

    private func syncRegistrationState(_ state: RegistrationState) {
        switch state {
        case .unavailable, .available:
            connectionState = .disconnected
        case .registering:
            connectionState = .registering
        case .registered:
            connectionState = .registered
        @unknown default:
            connectionState = .disconnected
        }
    }

    private func setError(_ message: String) {
        logger.error("Glasses error: \(message)")
        errorMessage = message
        showError = true
        connectionState = .error(message)
    }
}
