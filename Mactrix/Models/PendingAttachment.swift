import AppKit
import AVFoundation
import MatrixRustSDK
import UniformTypeIdentifiers

struct PendingAttachment: Identifiable {
    let id = UUID()
    let filename: String
    let data: Data
    let mimeType: String
    let uti: UTType
    let preview: NSImage?

    var isImage: Bool { uti.conforms(to: .image) }
    var isVideo: Bool { uti.conforms(to: .movie) }
    var isAudio: Bool { uti.conforms(to: .audio) }

    var uploadSource: UploadSource {
        .data(bytes: data, filename: filename)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    /// Extract duration (seconds) and optional video dimensions from an AV file.
    func avMetadata() async -> (duration: TimeInterval, width: UInt64?, height: UInt64?) {
        let url = writeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0

        if isVideo, let track = try? await asset.loadTracks(withMediaType: .video).first {
            let size = try? await track.load(.naturalSize)
            return (seconds, size.map { UInt64($0.width) }, size.map { UInt64($0.height) })
        }
        return (seconds, nil, nil)
    }

    /// Generate a blurhash from the first frame of a video.
    func videoBlurhash() async -> String? {
        let url = writeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 32, height: 32)
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            .blurHash(numberOfComponents: (3, 3))
    }

    // MARK: - Factory methods

    static func fromPasteboard() -> PendingAttachment? {
        let pb = NSPasteboard.general

        // PNG
        if let data = pb.data(forType: .png), let image = NSImage(data: data) {
            return PendingAttachment(filename: generatedName("png"), data: data, mimeType: "image/png", uti: .png, preview: image)
        }

        // JPEG
        if let data = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")), let image = NSImage(data: data) {
            return PendingAttachment(filename: generatedName("jpg"), data: data, mimeType: "image/jpeg", uti: .jpeg, preview: image)
        }

        // File URL
        if let urlString = pb.string(forType: .fileURL),
           let url = URL(string: urlString) {
            return fromFileURL(url)
        }

        return nil
    }

    static func fromFileURL(_ url: URL) -> PendingAttachment? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let uti = UTType(filenameExtension: url.pathExtension),
              let data = try? Data(contentsOf: url) else { return nil }
        let mime = uti.preferredMIMEType ?? "application/octet-stream"
        var preview: NSImage? = nil
        if uti.conforms(to: .image) {
            preview = NSImage(data: data)
        } else if uti.conforms(to: .movie) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 200, height: 200)
            if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                preview = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        return PendingAttachment(filename: url.lastPathComponent, data: data, mimeType: mime, uti: uti, preview: preview)
    }

    private static func generatedName(_ ext: String) -> String {
        "pasted-\(Int(Date().timeIntervalSince1970)).\(ext)"
    }

    private func writeTempFile() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
        return url
    }
}
