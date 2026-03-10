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

    public init(room: MatrixRustSDK.Room) {
        self.id = room.id()
        self.room = room

        Task {
            do {
                roomInfo = try await room.roomInfo()
            } catch {
                Logger.SidebarRoom.error("Failed to fetch initial room info: \(error)")
            }

            listenToRoomInfo()
        }
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
