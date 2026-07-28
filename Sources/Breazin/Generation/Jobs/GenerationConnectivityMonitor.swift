@preconcurrency import Network

actor GenerationConnectivityMonitor {
    static let shared = GenerationConnectivityMonitor()

    private let monitor: NWPathMonitor
    private var isSatisfied = true

    init() {
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            Task { await self?.update(isSatisfied: isSatisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "com.writish.breazin.generation-connectivity"))
    }

    deinit {
        monitor.cancel()
    }

    func isOnline() -> Bool {
        isSatisfied
    }

    private func update(isSatisfied: Bool) {
        self.isSatisfied = isSatisfied
    }
}
