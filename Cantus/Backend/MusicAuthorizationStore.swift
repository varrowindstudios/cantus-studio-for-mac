import Foundation
import MusicKit

@MainActor
final class MusicAuthorizationStore: ObservableObject {
    @Published private(set) var status: MusicAuthorization.Status = MusicAuthorization.currentStatus

    func refresh() {
        status = MusicAuthorization.currentStatus
    }

    func requestAuthorization() async {
        let newStatus = await MusicAuthorization.request()
        status = newStatus
    }

    var statusLabel: String {
        switch status {
        case .authorized:
            return "Connected"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Connected"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unknown"
        }
    }

    var isConnected: Bool {
        status == .authorized
    }
}
