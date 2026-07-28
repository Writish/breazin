import Foundation

struct GenerationRetryPolicy: Equatable, Sendable {
    let baseDelay: TimeInterval
    let maximumDelay: TimeInterval
    let jitterRatio: Double
    let offlinePollInterval: TimeInterval

    static let `default` = GenerationRetryPolicy(
        baseDelay: 2,
        maximumDelay: 5 * 60,
        jitterRatio: 0.2,
        offlinePollInterval: 5
    )

    func delay(retryCount: Int, jitterUnit: Double) -> TimeInterval {
        let exponent = min(max(retryCount, 0), 30)
        let exponential = min(maximumDelay, baseDelay * pow(2, Double(exponent)))
        let normalizedJitter = min(max(jitterUnit, 0), 1)
        let multiplier = 1 + ((normalizedJitter * 2) - 1) * jitterRatio
        return min(maximumDelay, max(0, exponential * multiplier))
    }

    func retryDate(
        retryCount: Int,
        now: Date,
        jitterUnit: Double
    ) -> Date {
        now.addingTimeInterval(delay(retryCount: retryCount, jitterUnit: jitterUnit))
    }

    func remainingDelay(nextRetryAt: Date?, now: Date) -> TimeInterval? {
        guard let nextRetryAt else { return nil }
        let delay = nextRetryAt.timeIntervalSince(now)
        return delay > 0 ? delay : nil
    }

    func isPermanent(_ error: any Error) -> Bool {
        guard let providerError = error as? ProviderGenerationError else { return false }
        return switch providerError {
        case .missingCredential, .unsupportedModel, .unsupportedInput:
            true
        case .invalidResponse, .remote:
            false
        }
    }
}
