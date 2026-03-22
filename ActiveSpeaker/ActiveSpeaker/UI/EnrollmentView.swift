import SwiftUI
import Vision

/// Tab view for enrolling faces. Users enter a name, take photos of themselves,
/// and the system stores facial embeddings for later recognition.
struct EnrollmentView: View {

    @ObservedObject var gallery: FaceGallery
    @ObservedObject var captureManager: CaptureManager

    @State private var enrollName: String = ""
    @State private var statusMessage: String = ""
    @State private var isCapturing: Bool = false

    /// Shared detection provider for enrollment face detection.
    private let detectionProvider = FaceDetectionProvider()

    /// Embedding processor reference — set externally via the environment
    /// or passed in. For enrollment we only need `generateEmbedding`.
    var embeddingProcessor: FaceEmbeddingProcessor?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Snapshot-based preview — avoids creating a second
                // AVCaptureVideoPreviewLayer which would freeze the app
                // and cause a black screen on the Camera tab.
                SnapshotPreviewView(captureManager: captureManager)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.top)

                // Status message
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }

                // Enrollment controls
                HStack {
                    TextField("Name", text: $enrollName)
                        .textFieldStyle(.roundedBorder)

                    Button(action: captureEmbedding) {
                        Image(systemName: "camera.circle.fill")
                            .font(.title)
                    }
                    .disabled(enrollName.trimmingCharacters(in: .whitespaces).isEmpty || isCapturing)
                }
                .padding()

                // Enrolled faces list
                List {
                    ForEach(gallery.allNames, id: \.self) { name in
                        HStack {
                            Text(name)
                                .font(.body)
                            Spacer()
                            Text("\(gallery.embeddingCount(forName: name)) photos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onDelete(perform: deleteEntries)
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Enroll Faces")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Actions

    private func captureEmbedding() {
        let name = enrollName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        guard let pixelBuffer = captureManager.latestPixelBuffer else {
            statusMessage = "No camera frame available"
            return
        }

        isCapturing = true
        statusMessage = "Processing..."

        // Run face detection + embedding on a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            let faces = detectionProvider.detectFaces(
                in: pixelBuffer,
                orientation: .leftMirrored
            )

            if faces.isEmpty {
                DispatchQueue.main.async {
                    statusMessage = "No face detected — try again"
                    isCapturing = false
                }
                return
            }

            if faces.count > 1 {
                DispatchQueue.main.async {
                    statusMessage = "Multiple faces detected — only you should be in frame"
                    isCapturing = false
                }
                return
            }

            let face = faces[0]

            guard let embedding = embeddingProcessor?.generateEmbedding(
                from: pixelBuffer,
                boundingBox: face.boundingBox
            ) else {
                DispatchQueue.main.async {
                    statusMessage = "Failed to generate embedding"
                    isCapturing = false
                }
                return
            }

            DispatchQueue.main.async {
                gallery.addEmbedding(embedding, forName: name)
                let count = gallery.embeddingCount(forName: name)
                statusMessage = "Captured! (\(count)/5 photos for \(name))"
                isCapturing = false
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        let names = gallery.allNames
        for offset in offsets {
            gallery.removeAll(forName: names[offset])
        }
    }
}
