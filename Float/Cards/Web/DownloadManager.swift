import Foundation
import WebKit

/// Saves a card's downloads to ~/Downloads and reports progress, completion and failure.
@MainActor
final class DownloadManager: NSObject, WKDownloadDelegate {
    enum Event {
        case progress(name: String, fraction: Double)
        case finished(URL)
        case failed(name: String, Error)
    }

    var onEvent: ((Event) -> Void)?
    private var names: [ObjectIdentifier: String] = [:]
    private var destinations: [ObjectIdentifier: URL] = [:]
    private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    func track(_ download: WKDownload) {
        download.delegate = self
        let id = ObjectIdentifier(download)
        observations[id] = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            DispatchQueue.main.async {
                guard let self, let name = self.names[id] else { return }
                self.onEvent?(.progress(name: name, fraction: fraction))
            }
        }
    }

    /// "report.pdf" → "report (1).pdf" etc. until `exists` says the name is free.
    nonisolated static func uniqueURL(for filename: String, in directory: URL, exists: (URL) -> Bool) -> URL {
        let name = filename.isEmpty ? "download" : filename
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var n = 1
        while exists(candidate) {
            candidate = directory.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        return candidate
    }

    func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse,
        suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void
    ) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let url = Self.uniqueURL(for: suggestedFilename, in: dir) { FileManager.default.fileExists(atPath: $0.path) }
        let id = ObjectIdentifier(download)
        names[id] = url.lastPathComponent
        destinations[id] = url
        onEvent?(.progress(name: url.lastPathComponent, fraction: 0))
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        if let url = destinations[id] { onEvent?(.finished(url)) }
        forget(id)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let id = ObjectIdentifier(download)
        onEvent?(.failed(name: names[id] ?? "download", error))
        forget(id)
    }

    private func forget(_ id: ObjectIdentifier) {
        names[id] = nil
        destinations[id] = nil
        observations[id] = nil
    }
}
