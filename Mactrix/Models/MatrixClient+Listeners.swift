import Foundation
import MatrixRustSDK
import OSLog

extension MatrixClient {
    func updateRoomEntries(roomEntriesUpdate: [RoomListEntriesUpdate]) async {
        for update in roomEntriesUpdate {
            switch update {
            case let .append(values):
                self.rooms.append(contentsOf: await makeRooms(values))
            case .clear:
                self.rooms.removeAll()
            case let .pushFront(room):
                self.rooms.insert(await SidebarRoom.make(room: room), at: 0)
            case let .pushBack(room):
                self.rooms.append(await SidebarRoom.make(room: room))
            case .popFront:
                self.rooms.removeFirst()
            case .popBack:
                self.rooms.removeLast()
            case let .insert(index, room):
                self.rooms.insert(await SidebarRoom.make(room: room), at: Int(index))
            case let .set(index, room):
                let existing = self.rooms[Int(index)]
                if existing.id == room.id() {
                    existing.updateRoom(room)
                } else {
                    self.rooms[Int(index)] = await SidebarRoom.make(room: room)
                }
            case let .remove(index):
                self.rooms.remove(at: Int(index))
            case let .truncate(length):
                self.rooms.removeSubrange(Int(length) ..< self.rooms.count)
            case let .reset(values: values):
                let existingById = Dictionary(uniqueKeysWithValues: self.rooms.map { ($0.id, $0) })
                var newRooms: [SidebarRoom] = []
                for room in values {
                    if let existing = existingById[room.id()] {
                        existing.updateRoom(room)
                        newRooms.append(existing)
                    } else {
                        newRooms.append(await SidebarRoom.make(room: room))
                    }
                }
                self.rooms = newRooms
            }
        }
    }

    /// Creates SidebarRoom instances in parallel while preserving order.
    private func makeRooms(_ rooms: [MatrixRustSDK.Room]) async -> [SidebarRoom] {
        await withTaskGroup(of: (Int, SidebarRoom).self) { group in
            for (index, room) in rooms.enumerated() {
                group.addTask { (index, await SidebarRoom.make(room: room)) }
            }
            var result: [(Int, SidebarRoom)] = []
            for await item in group { result.append(item) }
            return result.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
}

extension MatrixClient: SyncServiceStateObserver {
    nonisolated func onUpdate(state: MatrixRustSDK.SyncServiceState) {
        Task { @MainActor in
            syncState = state
        }
    }
}

extension MatrixClient: VerificationStateListener {
    nonisolated func onUpdate(status: MatrixRustSDK.VerificationState) {
        Task { @MainActor in
            verificationState = status
        }
    }
}

extension MatrixClient: RoomListServiceStateListener {
    nonisolated func onUpdate(state: MatrixRustSDK.RoomListServiceState) {
        Task { @MainActor in
            roomListServiceState = state
        }
    }
}

extension MatrixClient: RoomListServiceSyncIndicatorListener {
    nonisolated func onUpdate(syncIndicator: MatrixRustSDK.RoomListServiceSyncIndicator) {
        Task { @MainActor in
            showRoomSyncIndicator = syncIndicator
        }
    }
}

extension MatrixClient: MatrixRustSDK.ClientDelegate {
    nonisolated func didReceiveAuthError(isSoftLogout: Bool) {
        Task { @MainActor in
            Logger.matrixClient.debug("did receive auth error: soft logout \(isSoftLogout, privacy: .public)")
            if !isSoftLogout {
                authenticationFailed = true
            }
        }
    }
}

extension MatrixClient: MatrixRustSDK.IgnoredUsersListener {
    nonisolated func call(ignoredUserIds: [String]) {
        Task { @MainActor in
            Logger.matrixClient.debug("Updated ignored users: \(ignoredUserIds)")
            self.ignoredUserIds = ignoredUserIds
        }
    }
}

extension MatrixClient: SessionVerificationControllerDelegate {
    nonisolated func didReceiveVerificationRequest(details: MatrixRustSDK.SessionVerificationRequestDetails) {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didReceiveVerificationRequest")
            sessionVerificationRequest = details
        }
    }

    nonisolated func didAcceptVerificationRequest() {
        Logger.matrixClient.debug("session verification: didAcceptVerificationRequest")
    }

    nonisolated func didStartSasVerification() {
        Logger.matrixClient.debug("session verification: didStartSasVerification")
    }

    nonisolated func didReceiveVerificationData(data: MatrixRustSDK.SessionVerificationData) {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didReceiveVerificationData")
            sessionVerificationData = data
        }
    }

    nonisolated func didFail() {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didFail")
            sessionVerificationRequest = nil
            sessionVerificationData = nil
        }
    }

    nonisolated func didCancel() {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didCancel")
            sessionVerificationRequest = nil
            sessionVerificationData = nil
        }
    }

    nonisolated func didFinish() {
        Task { @MainActor in
            Logger.matrixClient.debug("session verification: didFinish")
            sessionVerificationRequest = nil
            sessionVerificationData = nil
        }
    }
}
