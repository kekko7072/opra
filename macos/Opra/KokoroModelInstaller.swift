//
//  KokoroModelInstaller.swift
//  Opra
//
//  Downloads and manages the on-device Kokoro model + voice files in Application
//  Support. Assets come from the mlx-community/Kokoro-82M-bf16 HuggingFace repo
//  (MLX-format safetensors). The model is ~327 MB; voices are small.
//

import Foundation

@MainActor
final class KokoroModelInstaller: ObservableObject {
    @Published private(set) var state: ModelInstallState = .notInstalled

    static let modelFileName = "kokoro-v1_0.safetensors"
    /// Default bundled voice set (filenames under the repo's `voices/` folder).
    static let voiceNames = ["af_heart", "af_bella", "am_michael", "bf_emma"]

    // VERIFY: source repository for the MLX-format model + voices.
    private let baseURL = "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main"

    private var task: Task<Void, Never>?
    private let downloader = AssetDownloader()

    var engineDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Opra/Engines/Kokoro", isDirectory: true)
    }
    var modelURL: URL { engineDirectory.appendingPathComponent(Self.modelFileName) }
    func voiceURL(_ name: String) -> URL {
        engineDirectory.appendingPathComponent("voices/\(name).safetensors")
    }

    init() { refreshState() }

    func refreshState() {
        if case .downloading = state { return }
        let fm = FileManager.default
        let hasModel = fm.fileExists(atPath: modelURL.path)
        let hasVoice = fm.fileExists(atPath: voiceURL(Self.voiceNames[0]).path)
        state = (hasModel && hasVoice) ? .installed : .notInstalled
    }

    func install() {
        guard task == nil else { return }
        state = .downloading(0)
        task = Task { await self.run() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .notInstalled
    }

    func remove() {
        try? FileManager.default.removeItem(at: engineDirectory)
        state = .notInstalled
    }

    private func run() async {
        defer { task = nil }
        do {
            try FileManager.default.createDirectory(
                at: engineDirectory.appendingPathComponent("voices"),
                withIntermediateDirectories: true
            )
            // Model is the bulk of the download → 0...0.85.
            try await downloader.download(
                from: URL(string: "\(baseURL)/\(Self.modelFileName)")!,
                to: modelURL
            ) { [weak self] frac in
                self?.state = .downloading(frac * 0.85)
            }
            // Voices → 0.85...1.0.
            let count = Self.voiceNames.count
            for (i, name) in Self.voiceNames.enumerated() {
                try Task.checkCancellation()
                let lo = 0.85 + 0.15 * Double(i) / Double(count)
                let hi = 0.85 + 0.15 * Double(i + 1) / Double(count)
                try await downloader.download(
                    from: URL(string: "\(baseURL)/voices/\(name).safetensors")!,
                    to: voiceURL(name)
                ) { [weak self] frac in
                    self?.state = .downloading(lo + frac * (hi - lo))
                }
            }
            state = .installed
        } catch is CancellationError {
            state = .notInstalled
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// Delegate-based single-file downloader with byte-level progress.
private final class AssetDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL?
    private var progress: (@MainActor (Double) -> Void)?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    func download(from url: URL, to dest: URL, progress: @escaping @MainActor (Double) -> Void) async throws {
        self.destination = dest
        self.progress = progress
        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.continuation = cont
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let frac = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let handler = progress
        Task { @MainActor in handler?(frac) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let destination else { continuation?.resume(); continuation = nil; return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
