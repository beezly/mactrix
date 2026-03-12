import AVKit
import MatrixRustSDK
import Models
import OSLog
import SwiftUI

struct MessageVideoView: View {
    @Environment(AppState.self) private var appState
    let content: VideoMessageContent

    @State private var fileHandle: MediaFileHandle?
    @State private var video: AVPlayer?
    @State private var generatedThumbnail: Image?

    var aspectRatio: CGFloat? {
        guard let info = content.info,
              let height = info.height,
              let width = info.width else { return nil }

        return CGFloat(width) / CGFloat(height)
    }

    var maxHeight: CGFloat {
        guard let height = content.info?.height else { return 300 }
        return min(CGFloat(height), 300)
    }

    func loadVideo() async {
        guard let client = appState.matrixClient?.client else { return }

        do {
            let handle = try await client.getMediaFile(
                mediaSource: content.source,
                filename: content.filename,
                mimeType: content.info?.mimetype ?? "",
                useCache: true,
                tempDir: NSTemporaryDirectory()
            )

            fileHandle = handle
            let path = try handle.path()
            let url = URL(filePath: path, directoryHint: .notDirectory)

            video = AVPlayer(url: url)
            video?.play()
        } catch {
            Logger.viewCycle.error("Failed to load video: \(error)")
        }
    }

    private func generateThumbnail() async {
        guard let client = appState.matrixClient?.client else { return }

        let cacheKey = NSString(string: "thumb:" + content.source.url())
        if let cached = MatrixClient.imageCache.object(forKey: cacheKey) {
            generatedThumbnail = Image(nsImage: cached)
            return
        }

        do {
            let handle = try await client.getMediaFile(
                mediaSource: content.source,
                filename: content.filename,
                mimeType: content.info?.mimetype ?? "",
                useCache: true,
                tempDir: NSTemporaryDirectory()
            )
            fileHandle = handle
            let path = try handle.path()
            let url = URL(filePath: path, directoryHint: .notDirectory)

            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)

            let cgImage = try await generator.image(at: .zero).image
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            MatrixClient.imageCache.setObject(nsImage, forKey: cacheKey)
            generatedThumbnail = Image(nsImage: nsImage)
        } catch {
            Logger.viewCycle.error("Failed to generate video thumbnail: \(error)")
        }
    }

    @ViewBuilder
    var thumbnailView: some View {
        if let thumbnailSource = content.info?.thumbnailSource {
            MatrixImageView(mediaSource: thumbnailSource, mimeType: content.info?.thumbnailInfo?.mimetype)
        } else if let generatedThumbnail {
            generatedThumbnail.resizable().scaledToFit()
        } else {
            Rectangle().fill(Color.gray.opacity(0.3))
        }
    }

    var body: some View {
        VStack {
            if let video {
                TimelineVideoPlayer(videoPlayer: video)
                    .cornerRadius(6)
            } else {
                Button(action: { Task { await loadVideo() } }) {
                    thumbnailView
                        .overlay {
                            Image(systemName: "play.fill")
                                .resizable()
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                                .frame(width: 48, height: 48)
                                .opacity(0.9)
                        }
                }
                .buttonStyle(.plain)
            }
            if let caption = content.caption, !caption.isEmpty {
                Text(caption.formatAsMarkdown)
                    .textSelection(.enabled)
            }
        }
        .frame(maxHeight: maxHeight)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .task(id: content.source.url(), priority: .utility) {
            if content.info?.thumbnailSource == nil {
                await generateThumbnail()
            }
        }
    }
}
