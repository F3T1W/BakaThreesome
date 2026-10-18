import Foundation

public enum SVPInterpolationStatus: Sendable, Equatable {
    case disabled
    case waiting
    case connected
    case interpolating(sourceFPS: Double, outputFPS: Double)

    static func inspect(filters: MPVValue, sourceFPS: Double?, outputFPS: Double?) -> Self {
        guard case .array(let filters) = filters,
              filters.contains(where: {
                  guard case .object(let filter) = $0,
                        filter["name"] == .string("vapoursynth"),
                        filter["label"] == .string("svp"),
                        filter["enabled"] != .bool(false) else { return false }
                  return true
              }) else { return .waiting }
        guard let sourceFPS, let outputFPS, sourceFPS.isFinite, outputFPS.isFinite,
              sourceFPS > 0, outputFPS > sourceFPS + 0.5 else { return .connected }
        return .interpolating(sourceFPS: sourceFPS, outputFPS: outputFPS)
    }
}
