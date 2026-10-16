import Foundation

/// Progress (or failure) of a built-in model download, kept in `AppState` for the Settings tab.
public struct ModelDownload: Equatable, Sendable {
    public let modelID: String
    public var fraction = 0.0
    public var error: String?

    public init(modelID: String) {
        self.modelID = modelID
    }
}

/// Downloads a built-in model into Application Support. One download at a time.
@MainActor
public final class ModelDownloader {
    private let state: AppState
    private var task: Task<Void, Never>?

    public init(state: AppState) {
        self.state = state
    }

    public func download(_ model: LocalModel) {
        guard task == nil else { return }
        state.setModelDownload(ModelDownload(modelID: model.id))
        task = Task {
            defer { task = nil }
            do {
                try await fetch(model)
                state.setModelDownload(nil)
            } catch is CancellationError {
                state.setModelDownload(nil)
            } catch let error as URLError where error.code == .cancelled {
                state.setModelDownload(nil)
            } catch {
                var failed = ModelDownload(modelID: model.id)
                failed.error = error.localizedDescription
                state.setModelDownload(failed)
            }
        }
    }

    public func cancel() {
        task?.cancel()
    }

    public func delete(_ model: LocalModel) {
        try? FileManager.default.removeItem(at: LocalModels.fileURL(model))
        state.setModelDownload(nil)
    }

    private func fetch(_ model: LocalModel) async throws {
        let progress = ProgressReporter { [state] fraction in
            Task { @MainActor in
                guard var current = state.modelDownload, current.modelID == model.id, current.error == nil else { return }
                current.fraction = fraction
                state.setModelDownload(current)
            }
        }
        guard let url = model.url else { throw ChatError("\(model.name) can't be downloaded; it has to be copied in by hand.") }
        let (temp, response) = try await URLSession.shared.download(from: url, delegate: progress)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: temp)
            throw ChatError("Download failed. Check your connection and try again.")
        }
        let size = (try? temp.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init)
        guard size == model.bytes else {
            try? FileManager.default.removeItem(at: temp)
            throw ChatError("The download was incomplete. Try again.")
        }
        try FileManager.default.createDirectory(at: LocalModels.folder, withIntermediateDirectories: true)
        let destination = LocalModels.fileURL(model)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }
}

/// Forwards a download task's fraction complete.
private final class ProgressReporter: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [report] progress, _ in
            report(progress.fractionCompleted)
        }
    }
}
