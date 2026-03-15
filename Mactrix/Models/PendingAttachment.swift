import AppKit
import AVFoundation
import MatrixRustSDK
import UniformTypeIdentifiers

struct PendingAttachment: Identifiable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let uti: UTType
    let preview: NSImage?
    let size: Int
    /// On-disk URL (temp copy for file picker items). Nil for pasteboard items.
    let sourceURL: URL?
    /// In-memory data (pasteboard items only). Nil when sourceURL is set.
    let data: Data?

    var isImage: Bool { uti.conforms(to: .image) }
    var isVideo: Bool { uti.conforms(to: .movie) }
    var isAudio: Bool { uti.conforms(to: .audio) }

    var uploadSource: UploadSource {
        if let sourceURL {
            return .file(filename: sourceURL.path(percentEncoded: false))
        }
        return .data(bytes: data!, filename: filename)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    // MARK: - Metadata for SDK info types

    func imageInfo() async -> ImageInfo {
        let blurhash = await imageBlurhash()
        return ImageInfo(
            height: preview.map { UInt64($0.size.height) },
            width: preview.map { UInt64($0.size.width) },
            mimetype: mimeType, size: UInt64(size),
            thumbnailInfo: nil, thumbnailSource: nil,
            blurhash: blurhash, isAnimated: false
        )
    }

    func videoInfo() async -> VideoInfo {
        let meta = await videoMetadata()
        return VideoInfo(
            duration: meta.duration, height: meta.height, width: meta.width,
            mimetype: mimeType, size: UInt64(size),
            thumbnailInfo: nil, thumbnailSource: nil, blurhash: meta.blurhash
        )
    }

    func audioInfo() async -> AudioInfo {
        let duration = await audioDuration()
        return AudioInfo(duration: duration, size: UInt64(size), mimetype: mimeType)
    }

    func fileInfo() -> FileInfo {
        FileInfo(mimetype: mimeType, size: UInt64(size), thumbnailInfo: nil, thumbnailSource: nil)
    }

    // MARK: - Private metadata helpers

    private func imageBlurhash() async -> String? {
        guard let image = preview else { return nil }
        return await Task.detached {
            let s = 32
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let ctx = CGContext(data: nil, width: s, height: s,
                                     bitsPerComponent: 8, bytesPerRow: s * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil as String? }
            ctx.interpolationQuality = .low
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: s, height: s))
            guard let smallCG = ctx.makeImage() else { return nil }
            return NSImage(cgImage: smallCG, size: NSSize(width: s, height: s))
                .blurHash(numberOfComponents: (3, 3))
        }.value
    }

    private func videoMetadata() async -> (duration: TimeInterval, width: UInt64?, height: UInt64?, blurhash: String?) {
        let url = avURL()
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0

        var w: UInt64?, h: UInt64?
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize) {
            w = UInt64(size.width)
            h = UInt64(size.height)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 32, height: 32)
        var blurhash: String?
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            blurhash = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                .blurHash(numberOfComponents: (3, 3))
        }

        return (seconds, w, h, blurhash)
    }

    private func audioDuration() async -> TimeInterval {
        (try? await AVURLAsset(url: avURL()).load(.duration).seconds) ?? 0
    }

    /// Returns sourceURL if available, otherwise writes data to a temp file.
    private func avURL() -> URL {
        if let sourceURL { return sourceURL }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data?.write(to: url)
        return url
    }

    // MARK: - Factory methods

    static func fromPasteboard() -> PendingAttachment? {
        let pb = NSPasteboard.general

        if let data = pb.data(forType: .png), let image = NSImage(data: data) {
            return PendingAttachment(filename: generatedName("png"), mimeType: "image/png", uti: .png, preview: image, size: data.count, sourceURL: nil, data: data)
        }

        if let data = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")), let image = NSImage(data: data) {
            return PendingAttachment(filename: generatedName("jpg"), mimeType: "image/jpeg", uti: .jpeg, preview: image, size: data.count, sourceURL: nil, data: data)
        }

        if let urlString = pb.string(forType: .fileURL), let url = URL(string: urlString) {
            return fromFileURL(url)
        }

        return nil
    }

    static func fromFileURL(_ url: URL) -> PendingAttachment? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let uti = UTType(filenameExtension: url.pathExtension),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let fileSize = attrs[.size] as? Int else { return nil }

        let mime = uti.preferredMIMEType ?? "application/octet-stream"

        // Copy to temp so the file remains accessible after security scope ends
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tempURL)
        guard (try? FileManager.default.copyItem(at: url, to: tempURL)) != nil else { return nil }

        var preview: NSImage? = nil
        if uti.conforms(to: .image) {
            preview = NSImage(contentsOf: tempURL)
        } else if uti.conforms(to: .movie) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: tempURL))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 200, height: 200)
            if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                preview = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }

        return PendingAttachment(filename: url.lastPathComponent, mimeType: mime, uti: uti, preview: preview, size: fileSize, sourceURL: tempURL, data: nil)
    }

    private static func generatedName(_ ext: String) -> String {
        "pasted-\(Int(Date().timeIntervalSince1970)).\(ext)"
    }
}
