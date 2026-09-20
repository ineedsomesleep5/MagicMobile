import Foundation
import Combine

/// The system owns transfers; the app owns a durable manifest and append-only result journal.
@MainActor final class NativeArtworkBackgroundQueue: ObservableObject {
    static let sessionIdentifier = "com.calebfeliciano.magicmobile.artwork.v1"
    static let didStoreImage = Notification.Name("MagicMobileArtworkImageStored")
    static let shared = NativeArtworkBackgroundQueue(allowNetwork: {
        #if canImport(UIKit)
        MagicMobilePreferences.current.bool(forKey: "magicmobile.deckArtworkNetworkEnabled")
        #else
        UserDefaults.standard.bool(forKey: "magicmobile.deckArtworkNetworkEnabled")
        #endif
    })
    struct Entry: Codable {
        let key: String
        let name: String
        let url: URL
        let quality: NativeArtworkQuality
    }
    private struct Job: Codable { let id: UUID; let entries: [Entry] }
    @Published private(set) var isRunning = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var failures = 0
    @Published private(set) var failureMessages: [String] = []
    @Published private(set) var status = ""
    private let directory: URL
    private let store: NativeAssetStore
    private let allowNetwork: () -> Bool
    private var nextIndex = 0
    private var job: Job?
    private var finished = Set<Int>()
    private var saving = Set<Int>()
    private var reconciling = false
    private var needsReconcile = false
    private var backgroundEventsFinished = false
    private var backgroundCompletion: (() -> Void)?
    private let delegate: ArtworkTransferDelegate
    private var session: URLSession!
    private var manifestURL: URL { directory.appendingPathComponent("job.json") }
    private var journalURL: URL { directory.appendingPathComponent("results.log") }
    private var cancelledURL: URL { directory.appendingPathComponent("cancelled") }
    private var retryURL: URL { directory.appendingPathComponent("retry-after.json") }
    private enum QueueError: LocalizedError {
        case retryLater
        var errorDescription: String? { "The image service requested a pause. Please try again later." }
    }

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ArtworkTransfers-v1"),
         store: NativeAssetStore = .shared, configuration: URLSessionConfiguration? = nil,
         allowNetwork: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: "magicmobile.deckArtworkNetworkEnabled") }) {
        self.directory = directory; self.store = store; self.allowNetwork = allowNetwork
        delegate = ArtworkTransferDelegate(directory: directory)
        let config = configuration ?? URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.httpMaximumConnectionsPerHost = 4
        config.isDiscretionary = false
        config.timeoutIntervalForResource = 7 * 24 * 60 * 60
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        delegate.owner = self
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: .main)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var location = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try location.setResourceValues(values)
            if FileManager.default.fileExists(atPath: manifestURL.path) {
                guard (try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 50 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
                let restored = try JSONDecoder().decode(Job.self, from: Data(contentsOf: manifestURL))
                guard Self.valid(restored.entries) else { throw URLError(.badURL) }
                job = restored; total = restored.entries.count
                if (try? journalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 <= 8 * 1024 * 1024,
                   let journal = try? String(contentsOf: journalURL, encoding: .utf8) {
                    for line in journal.split(separator: "\n") {
                        let parts = line.split(separator: ":")
                        if parts.count == 3, parts[0] == Substring(restored.id.uuidString), let index = Int(parts[1]), restored.entries.indices.contains(index), finished.insert(index).inserted {
                            if parts[2] == "ok" { completed += 1 } else {
                                failures += 1
                                if failureMessages.count < 100 { failureMessages.append(restored.entries[index].name) }
                            }
                        }
                    }
                }
                if !allowNetwork() { try Data().write(to: cancelledURL, options: .atomic) }
                isRunning = allowNetwork() && !FileManager.default.fileExists(atPath: cancelledURL.path) && finished.count < total
                status = isRunning ? "Downloading artwork" : (completed == total ? "Artwork is up to date" : "Download stopped")
            }
        } catch { status = "Could not restore downloads. Start a new download." }
        reconcile()
    }

    static func allowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.fragment == nil && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) &&
        url.host == "cards.scryfall.io"
    }
    private static func valid(_ entries: [Entry]) -> Bool {
        entries.count <= 100_000 && entries.allSatisfy { !$0.key.isEmpty && $0.key.utf8.count <= 1024 && $0.name.utf8.count <= 1024 && $0.url.absoluteString.utf8.count <= 4096 && allowed($0.url) } &&
        Set(entries.map(\.key)).count == entries.count
    }
    func start(entries: [Entry]) throws {
        guard allowNetwork() else { throw URLError(.userAuthenticationRequired) }
        if let data = try? Data(contentsOf: retryURL), let retry = try? JSONDecoder().decode(Date.self, from: data), retry > Date() { throw QueueError.retryLater }
        guard !isRunning, saving.isEmpty, Self.valid(entries) else { throw URLError(.badURL) }
        let next = Job(id: UUID(), entries: entries)
        try JSONEncoder().encode(next).write(to: manifestURL, options: .atomic)
        try Data().write(to: journalURL, options: .atomic)
        if FileManager.default.fileExists(atPath: cancelledURL.path) { try FileManager.default.removeItem(at: cancelledURL) }
        job = next; finished = []; completed = 0; failures = 0; failureMessages = []; total = entries.count; nextIndex = 0
        isRunning = !entries.isEmpty; status = entries.isEmpty ? "Artwork is up to date" : "Downloading artwork"
        reconcile()
    }
    func cancel() {
        // Persist cancellation before touching system tasks, so relaunch cannot restart consent-revoked work.
        do { try Data().write(to: cancelledURL, options: .atomic) }
        catch { try? FileManager.default.removeItem(at: manifestURL) }
        isRunning = false
        let prefix = job.map { $0.id.uuidString + "/" }
        session.getAllTasks { tasks in
            guard let prefix else { return }
            tasks.filter { $0.taskDescription?.hasPrefix(prefix) == true }.forEach { $0.cancel() }
        }
        status = "Download stopped"
        NotificationCenter.default.post(name: NativeAssetDownloads.didFinish, object: nil)
    }
    func reconnectBackgroundSession(completion: @escaping () -> Void) {
        backgroundCompletion = completion
        reconcile()
        finishBackgroundEventsIfReady()
    }
    fileprivate func eventsFinished() {
        backgroundEventsFinished = true
        reconcile()
        finishBackgroundEventsIfReady()
    }
    private func finishBackgroundEventsIfReady() {
        guard backgroundEventsFinished, saving.isEmpty, !reconciling, let completion = backgroundCompletion else { return }
        backgroundCompletion = nil; backgroundEventsFinished = false; completion()
    }
    private func index(_ description: String?) -> Int? {
        guard let job, let description else { return nil }
        let parts = description.split(separator: "/")
        guard parts.count == 2, parts[0] == Substring(job.id.uuidString), let index = Int(parts[1]), job.entries.indices.contains(index) else { return nil }
        return index
    }
    private func reconcile() {
        guard !reconciling else { needsReconcile = true; return }
        reconciling = true
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }
                if self.isRunning && !self.allowNetwork() { self.cancel() }
                var active = Set<Int>()
                for task in tasks {
                    guard self.isRunning, let index = self.index(task.taskDescription), !self.finished.contains(index), !active.contains(index) else { task.cancel(); continue }
                    active.insert(index)
                    if task.state == .suspended { task.resume() }
                }
                if self.isRunning, let job = self.job {
                    var slots = max(0, 64 - active.count - self.saving.count)
                    while slots > 0 && self.nextIndex < job.entries.count {
                        let index = self.nextIndex; self.nextIndex += 1
                        if self.finished.contains(index) || active.contains(index) || self.saving.contains(index) { continue }
                        var request = URLRequest(url: job.entries[index].url)
                        request.setValue("image/jpeg, image/png", forHTTPHeaderField: "Accept")
                        request.setValue("MagicMobile/0.1 ArtworkDownload", forHTTPHeaderField: "User-Agent")
                        let task = self.session.downloadTask(with: request)
                        task.taskDescription = "\(job.id.uuidString)/\(index)"
                        task.countOfBytesClientExpectsToReceive = Int64(job.entries[index].quality.estimatedBytes)
                        task.resume(); slots -= 1
                    }
                    if self.finished.count == job.entries.count && self.saving.isEmpty {
                        self.isRunning = false
                        self.status = self.failures == 0 ? "Artwork is up to date" : "\(self.failures) images could not download. Check missing artwork to retry."
                        NotificationCenter.default.post(name: NativeAssetDownloads.didFinish, object: nil)
                    }
                }
                self.reconciling = false
                if self.needsReconcile { self.needsReconcile = false; self.reconcile() }
                self.finishBackgroundEventsIfReady()
            }
        }
    }
    fileprivate func downloaded(description: String?, file: URL?, response: URLResponse?, stagingError: Error? = nil) {
        guard isRunning, let index = index(description), let job, !finished.contains(index), !saving.contains(index) else {
            if let file { try? FileManager.default.removeItem(at: file) }; return
        }
        saving.insert(index)
        let entry = job.entries[index]
        Task {
            var success = false
            defer { if let file { try? FileManager.default.removeItem(at: file) } }
            do {
                if stagingError != nil {
                    cancel(); status = "Download paused because its file could not be saved. Check device storage and try again."
                    throw CancellationError()
                }
                if let http = response as? HTTPURLResponse, [401, 403, 429, 503].contains(http.statusCode) {
                    if [429, 503].contains(http.statusCode) {
                        let retry = Date().addingTimeInterval(NativeDeckArtwork.retryDelay(http.value(forHTTPHeaderField: "Retry-After")))
                        try? JSONEncoder().encode(retry).write(to: retryURL, options: .atomic)
                    }
                    cancel()
                    status = http.statusCode == 429 ? "Download paused by the image service. Try again later." : "Image service unavailable. Try again later."
                    throw CancellationError()
                }
                guard let file, let response = response as? HTTPURLResponse,
                      let url = response.url, Self.allowed(url),
                      (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= NativeDeckArtwork.maximumBytes else { throw URLError(.badServerResponse) }
                try NativeDeckArtwork.validate(response)
                let bytes = try Data(contentsOf: file)
                guard isRunning, allowNetwork() else { throw CancellationError() }
                try await store.save(bytes, key: entry.key, quality: entry.quality)
                success = true
                NotificationCenter.default.post(name: Self.didStoreImage, object: nil,
                                                userInfo: ["key": entry.key, "name": entry.name])
            } catch let error as NativeAssetStore.StoreError {
                switch error {
                case .full, .lowDiskSpace: cancel(); status = error.localizedDescription
                case .invalidImage: break
                }
            } catch { /* The manifest preserves this entry for a later missing-artwork retry. */ }
            saving.remove(index)
            if self.job?.id == job.id && isRunning { record(index, success: success) }
            reconcile()
        }
    }
    fileprivate func failed(description: String?, error: Error) {
        guard isRunning, let index = index(description), !saving.contains(index), !finished.contains(index) else { return }
        if let error = error as? URLError, [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut, .secureConnectionFailed].contains(error.code) {
            cancel(); status = "Download paused. Check your connection and try again."; return
        }
        record(index, success: false); reconcile()
    }
    private func record(_ index: Int, success: Bool) {
        do {
            let handle = try FileHandle(forWritingTo: journalURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            guard let job else { return }
            try handle.write(contentsOf: Data("\(job.id.uuidString):\(index):\(success ? "ok" : "failed")\n".utf8))
            try handle.synchronize()
            finished.insert(index)
            if success { completed += 1 } else {
                failures += 1
                if failureMessages.count < 100 { failureMessages.append(job.entries[index].name) }
            }
        } catch { cancel(); status = "Download paused because its progress could not be saved." }
    }
}

private final class ArtworkTransferDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var owner: NativeArtworkBackgroundQueue?
    let directory: URL
    init(directory: URL) { self.directory = directory }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let file = directory.appendingPathComponent("transfer-\(UUID().uuidString).tmp")
        var moved: URL?
        var stagingError: Error?
        do { try FileManager.default.moveItem(at: location, to: file); moved = file } catch { stagingError = error }
        let staged = moved, description = downloadTask.taskDescription, response = downloadTask.response
        // This session explicitly uses OperationQueue.main. Register pending saves
        // synchronously so the later finish-events callback cannot overtake them.
        MainActor.assumeIsolated { owner?.downloaded(description: description, file: staged, response: response, stagingError: stagingError) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let description = task.taskDescription
        MainActor.assumeIsolated { owner?.failed(description: description, error: error) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > Int64(NativeDeckArtwork.maximumBytes) || totalBytesExpectedToWrite > Int64(NativeDeckArtwork.maximumBytes) { downloadTask.cancel() }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated { owner?.eventsFinished() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        MainActor.assumeIsolated { completionHandler(request.url.map(NativeArtworkBackgroundQueue.allowed) == true ? request : nil) }
    }
}
