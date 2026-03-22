import Foundation
import os

/// Persistent store for enrolled face embeddings.
///
/// Maps person names to arrays of embedding vectors (multiple enrollments
/// per person for robustness across angles/expressions).
///
/// Thread safety: all reads and writes go through an `os_unfair_lock`.
/// The gallery is read on the video processing queue and written on the main thread.
final class FaceGallery: ObservableObject {

    /// Published so SwiftUI enrollment UI reacts to changes.
    @Published private(set) var entries: [String: [[Float]]] = [:]

    private var _lock = os_unfair_lock()
    private let fileURL: URL

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        try? FileManager.default.createDirectory(
            at: appSupport, withIntermediateDirectories: true
        )
        self.fileURL = appSupport.appendingPathComponent("face_gallery.json")
        self.entries = Self.loadFromDisk(url: fileURL)
    }

    // MARK: - Read (thread-safe snapshot)

    /// Returns a snapshot of all entries. Safe to call from any queue.
    func snapshot() -> [String: [[Float]]] {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return entries
    }

    // MARK: - Write (call on main thread, persists automatically)

    func addEmbedding(_ embedding: [Float], forName name: String) {
        os_unfair_lock_lock(&_lock)
        entries[name, default: []].append(embedding)
        let copy = entries
        os_unfair_lock_unlock(&_lock)

        objectWillChange.send()
        saveToDisk(copy)
    }

    func removeAll(forName name: String) {
        os_unfair_lock_lock(&_lock)
        entries.removeValue(forKey: name)
        let copy = entries
        os_unfair_lock_unlock(&_lock)

        objectWillChange.send()
        saveToDisk(copy)
    }

    func removeLastEmbedding(forName name: String) {
        os_unfair_lock_lock(&_lock)
        entries[name]?.removeLast()
        if entries[name]?.isEmpty == true {
            entries.removeValue(forKey: name)
        }
        let copy = entries
        os_unfair_lock_unlock(&_lock)

        objectWillChange.send()
        saveToDisk(copy)
    }

    var allNames: [String] {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return Array(entries.keys).sorted()
    }

    func embeddingCount(forName name: String) -> Int {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return entries[name]?.count ?? 0
    }

    // MARK: - Persistence

    private func saveToDisk(_ data: [String: [[Float]]]) {
        DispatchQueue.global(qos: .utility).async { [fileURL] in
            do {
                let json = try JSONEncoder().encode(data)
                try json.write(to: fileURL, options: .atomic)
            } catch {
                print("[FaceGallery] Save failed: \(error)")
            }
        }
    }

    private static func loadFromDisk(url: URL) -> [String: [[Float]]] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [[Float]]].self, from: data)
        else { return [:] }
        return decoded
    }
}
