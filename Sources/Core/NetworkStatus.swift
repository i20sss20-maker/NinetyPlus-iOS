import Foundation
import Network

@MainActor
final class NetworkStatus: ObservableObject {
    static let shared = NetworkStatus()

    @Published private(set) var isOnline = true
    @Published private(set) var interfaceName: String? = nil

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.ninetyplus.network-status", qos: .utility)
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let interface: String?
            if path.usesInterfaceType(.wifi) { interface = "Wi‑Fi" }
            else if path.usesInterfaceType(.cellular) { interface = "شبكة الجوال" }
            else if path.usesInterfaceType(.wiredEthernet) { interface = "Ethernet" }
            else { interface = nil }

            Task { @MainActor in
                self?.isOnline = online
                self?.interfaceName = interface
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
