// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation

/// Downloads one pinned revision of a Hugging Face model repository into a folder.
///
/// Only the files a model needs to run are fetched. Each file is downloaded to a temporary
/// name and moved into place when complete, so an interrupted download is resumed file by file
/// and a half-written file is never loaded.
struct HuggingFaceDownload: Sendable {
    let repo: String
    /// A commit hash: the files never change under Typist after a review.
    let revision: String
    let folder: URL

    struct RemoteFile: Decodable {
        let type: String
        let path: String
        let size: Int64
    }

    enum DownloadError: Error, CustomStringConvertible {
        case badResponse(String, Int)
        case sizeMismatch(String)
        case badURL(String)

        var description: String {
            switch self {
            case .badResponse(let path, let status): "\(path): HTTP \(status)"
            case .sizeMismatch(let path): "\(path) downloaded incompletely"
            case .badURL(let path): "no address for \(path)"
            }
        }
    }

    static func wanted(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        guard !path.contains("/") else { return false }
        if name.hasSuffix(".safetensors") || name.hasSuffix(".jinja") || name.hasSuffix(".txt") { return true }
        // Image, video and audio preprocessors are for inputs Typist never sends.
        return name.hasSuffix(".json") && !name.contains("processor")
    }

    /// Whether every needed file of this revision is already on disk.
    var isComplete: Bool {
        (try? String(contentsOf: folder.appending(path: ".complete"), encoding: .utf8)) == revision
    }

    func run(progress: @escaping @Sendable (Double) -> Void) async throws {
        if isComplete { return }
        let files = try await list().filter { $0.type == "file" && Self.wanted($0.path) }
        let total = max(1, files.reduce(0) { $0 + $1.size })
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var done: Int64 = 0
        for file in files {
            let target = folder.appending(path: file.path)
            if let size = Self.size(of: target), size == file.size {
                done += file.size
                continue
            }
            let base = done
            try await fetch(file, to: target) { written in
                progress(Double(base + written) / Double(total))
            }
            done += file.size
            progress(Double(done) / Double(total))
        }
        FileManager.default.createFile(atPath: folder.appending(path: ".complete").path, contents: Data(revision.utf8))
    }

    private func list() async throws -> [RemoteFile] {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repo)/tree/\(revision)") else {
            throw DownloadError.badURL("file list")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw DownloadError.badResponse("file list", status) }
        return try JSONDecoder().decode([RemoteFile].self, from: data)
    }

    private func fetch(_ file: RemoteFile, to target: URL, written: @escaping @Sendable (Int64) -> Void) async throws {
        guard let url = URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file.path)") else {
            throw DownloadError.badURL(file.path)
        }
        let (temporary, response) = try await URLSession.shared.download(
            from: url, delegate: ProgressDelegate(written: written))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw DownloadError.badResponse(file.path, status) }
        guard Self.size(of: temporary) == file.size else { throw DownloadError.sizeMismatch(file.path) }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
    }

    private static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let written: @Sendable (Int64) -> Void

    init(written: @escaping @Sendable (Int64) -> Void) {
        self.written = written
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        written(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The async `download(from:delegate:)` call returns the file.
    }
}
