import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
public final class SidebarRoom: Identifiable {
    public let room: MatrixRustSDK.Room
    public var roomInfo: RoomInfo?

    @ObservationIgnored private var roomInfoHandle: TaskHandle?

    public nonisolated var id: String {
        room.id()
    }

    public init(room: MatrixRustSDK.Room) {
        self.room = room
        listenToRoomInfo()
    }

    private init(room: MatrixRustSDK.Room, initialRoomInfo: RoomInfo) {
        self.room = room
        self.roomInfo = initialRoomInfo
        listenToRoomInfo()
    }

    /// Creates a SidebarRoom with roomInfo pre-populated to avoid a nil flash on first render.
    public static func make(room: MatrixRustSDK.Room) async -> SidebarRoom {
        if let roomInfo = try? await room.roomInfo() {
            return SidebarRoom(room: room, initialRoomInfo: roomInfo)
        }
        return SidebarRoom(room: room)
    }

    private func listenToRoomInfo() {
        let listener = AsyncSDKListener<RoomInfo>()
        roomInfoHandle = room.subscribeToRoomInfoUpdates(listener: listener)

        Task { [weak self] in
            for await roomInfo in listener._throttle(for: .milliseconds(500)) {
                guard let self else { break }
                self.roomInfo = roomInfo
            }
        }
    }
}
