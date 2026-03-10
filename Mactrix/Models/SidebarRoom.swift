import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog

@MainActor @Observable
public final class SidebarRoom: Identifiable {
    public let id: String
    public nonisolated(unsafe) private(set) var room: MatrixRustSDK.Room
    public var roomInfo: RoomInfo?

    @ObservationIgnored private var roomInfoHandle: TaskHandle?

    private init(room: MatrixRustSDK.Room) {
        self.id = room.id()
        self.room = room
    }

    /// Synchronous init — fetches roomInfo async in background.
    /// Use when a nil flash is acceptable (e.g. LiveRoom).
    public static func create(room: MatrixRustSDK.Room) -> SidebarRoom {
        let instance = SidebarRoom(room: room)
        Task {
            do {
                instance.roomInfo = try await room.roomInfo()
            } catch {
                Logger.SidebarRoom.error("Failed to fetch initial room info: \(error)")
            }
            instance.listenToRoomInfo()
        }
        return instance
    }

    /// Async factory — pre-populates roomInfo before returning to avoid a nil flash.
    /// Use for room list entries where the room is rendered immediately.
    public static func make(room: MatrixRustSDK.Room) async -> SidebarRoom {
        let instance = SidebarRoom(room: room)
        instance.roomInfo = try? await room.roomInfo()
        instance.listenToRoomInfo()
        return instance
    }

    /// Updates the underlying room reference without replacing this instance.
    /// Preserves loaded state (roomInfo, subscription) while ensuring the
    /// room object is current.
    public func updateRoom(_ newRoom: MatrixRustSDK.Room) {
        assert(id == newRoom.id())
        room = newRoom
        roomInfoHandle = nil  // cancel old subscription
        listenToRoomInfo()    // re-subscribe on new room reference
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
