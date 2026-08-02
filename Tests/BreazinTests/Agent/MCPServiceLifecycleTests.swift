import Testing

@testable import Breazin

@Suite("MCP service lifecycle", .serialized)
@MainActor
struct MCPServiceLifecycleTests {
    @Test func stopWaitsForUnderlyingServerShutdown() async {
        let server = SuspendedMCPServer()
        let service = MCPService(projectProvider: { nil }, lifecycleServer: server)
        service.start()
        await server.waitUntilStarted()
        #expect(service.isRunning)

        let completion = LifecycleCompletion()
        let stopTask = Task { @MainActor in
            await service.stop()
            await completion.markFinished()
        }
        await server.waitUntilStopEntered()
        #expect(await !completion.isFinished)

        await server.finishStop()
        await stopTask.value
        #expect(await completion.isFinished)
        #expect(!service.isRunning)
    }
}

private actor SuspendedMCPServer: MCPServerLifecycle {
    private var started = false
    private var stopEntered = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopContinuation: CheckedContinuation<Void, Never>?

    func start() {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
    }

    func stop() async {
        stopEntered = true
        stopWaiters.forEach { $0.resume() }
        stopWaiters.removeAll()
        await withCheckedContinuation { stopContinuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func waitUntilStopEntered() async {
        guard !stopEntered else { return }
        await withCheckedContinuation { stopWaiters.append($0) }
    }

    func finishStop() {
        stopContinuation?.resume()
        stopContinuation = nil
    }
}

private actor LifecycleCompletion {
    private(set) var isFinished = false

    func markFinished() {
        isFinished = true
    }
}
