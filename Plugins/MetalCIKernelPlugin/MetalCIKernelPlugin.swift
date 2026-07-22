import Foundation
import PackagePlugin

/// Compiles Core Image Metal kernels (`Metal/*.metal`) into `.metallib` resources.
@main
struct MetalCIKernelPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let metalDir = context.package.directoryURL.appending(path: "Metal")
        // Keep inputs explicit. Directory enumeration from a build-tool plugin can
        // silently return no entries under newer SwiftPM plugin sandboxes, producing
        // a successful binary with every Core Image kernel missing at runtime.
        let names = [
            "ChromaKey.metal",
            "Clarity.metal",
            "Glow.metal",
            "GradeCurves.metal",
            "Grain.metal",
            "HighlightsShadows.metal",
            "HueCurves.metal",
            "LUTTetra.metal",
            "Levels.metal",
            "Vignette.metal",
            "Wheels.metal",
        ]

        return names.map { file in
            let stem = (file as NSString).deletingPathExtension
            let metal = metalDir.appending(path: file)
            let air = context.pluginWorkDirectoryURL.appending(path: "\(stem).air")
            let metallib = context.pluginWorkDirectoryURL.appending(path: "\(stem).metallib")
            return .buildCommand(
                displayName: "Compile CI kernel \(file)",
                executable: URL(filePath: "/bin/sh"),
                arguments: [
                    "-c",
                    "xcrun --toolchain Metal metal -c -fcikernel '\(metal.path(percentEncoded: false))' " +
                    "-o '\(air.path(percentEncoded: false))' && " +
                    "xcrun --toolchain Metal metallib -cikernel '\(air.path(percentEncoded: false))' " +
                    "-o '\(metallib.path(percentEncoded: false))'",
                ],
                inputFiles: [metal],
                outputFiles: [metallib])
        }
    }
}
