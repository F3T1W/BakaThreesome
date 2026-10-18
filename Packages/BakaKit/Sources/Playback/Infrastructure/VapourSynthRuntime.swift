import Foundation

/// Homebrew R81 moved VSScript into its Python package; mpv still needs its explicit path.
enum VapourSynthRuntime {
    static func environment() -> [String: String] {
        if let configured = ProcessInfo.processInfo.environment["VSSCRIPT_PATH"],
           FileManager.default.fileExists(atPath: configured) { return [:] }
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let base = URL(fileURLWithPath: prefix).appendingPathComponent("opt/vapoursynth")
            let legacy = base.appendingPathComponent("lib/libvapoursynth-script.dylib")
            if FileManager.default.fileExists(atPath: legacy.path) {
                return ["VSSCRIPT_PATH": legacy.path]
            }
            let pythonRoot = base.appendingPathComponent("libexec/lib")
            let versions = (try? FileManager.default.contentsOfDirectory(
                at: pythonRoot, includingPropertiesForKeys: nil
            )) ?? []
            for version in versions.sorted(by: { $0.path < $1.path }) where version.lastPathComponent.hasPrefix("python3.") {
                let library = version.appendingPathComponent("site-packages/vapoursynth/libvsscript.dylib")
                if FileManager.default.fileExists(atPath: library.path) {
                    return ["VSSCRIPT_PATH": library.path]
                }
            }
        }
        return [:]
    }
}
