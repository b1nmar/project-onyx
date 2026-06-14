// Copyright 2026 Onyx Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI
import os.log
#if canImport(UIKit)
import UIKit
#endif

// MARK: - OnyxApp

/// Application entry point.
@main
struct OnyxApp: App {

    static let log = Logger(subsystem: "ai.kiraa.onyx", category: "Lifecycle")

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // This is the FIRST Swift code that runs after dyld finishes loading.
        // If the app never reaches this point the crash is pre-main (dyld/ObjC
        // class registration). If this fires, the crash happens later in Swift.
        Self.log.notice("🟢 OnyxApp.init — Swift main reached")
        Self.writeBootStamp()
        Self.logBuildEnvironment()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    OnyxApp.log.notice("🟢 ContentView appeared — UI pipeline healthy")
                }
                .task {
                    // Start at launch if the user had the server enabled.
                    if OnyxSettings.shared.ollamaServerEnabled {
                        try? await OllamaServer.shared.start(
                            port: UInt16(OnyxSettings.shared.ollamaServerPort))
                    }
                    // React to the Settings toggle without needing a View modifier.
                    for await _ in NotificationCenter.default.notifications(
                        named: .ollamaServerSettingChanged) {
                        if OnyxSettings.shared.ollamaServerEnabled {
                            try? await OllamaServer.shared.start(
                                port: UInt16(OnyxSettings.shared.ollamaServerPort))
                        } else {
                            await OllamaServer.shared.stop()
                        }
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 650)
        #endif
        .onChange(of: scenePhase) { _, newPhase in
            Self.log.notice("📱 scenePhase → \(String(describing: newPhase), privacy: .public)")
            if newPhase == .background {
                Task {
                    await MLXModelManager.shared.unloadModel()
                    #if os(iOS)
                    await OllamaServer.shared.stop()
                    #endif
                }
            } else if newPhase == .active {
                #if os(iOS)
                Task {
                    if OnyxSettings.shared.ollamaServerEnabled {
                        try? await OllamaServer.shared.start(
                            port: UInt16(OnyxSettings.shared.ollamaServerPort))
                    }
                }
                #endif
            }
        }
    }

    // MARK: - Boot stamp

    /// Write a timestamped file to Documents so a future session (or a Mac
    /// inspecting the device via Xcode) can confirm Swift main ran.
    private static func writeBootStamp() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let stamp = docs.appendingPathComponent("boot-stamp.txt")
        let iso = ISO8601DateFormatter().string(from: Date())
        let line = "[\(iso)] OnyxApp.init reached — Swift main ran successfully\n"
        // Append so we accumulate a history of launch attempts.
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: stamp.path),
               let handle = try? FileHandle(forWritingTo: stamp) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: stamp)
            }
        }
        log.notice("📝 boot stamp written to \(stamp.path, privacy: .public)")
    }

    // MARK: - Environment diagnostics

    private static func logBuildEnvironment() {
        log.notice("🔧 bundle id  : \(Bundle.main.bundleIdentifier ?? "?", privacy: .public)")
        log.notice("🔧 build ver  : \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?", privacy: .public)")
        log.notice("🔧 short ver  : \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?", privacy: .public)")
        #if canImport(UIKit)
        log.notice("🔧 iOS        : \(UIDevice.current.systemVersion, privacy: .public)")
        log.notice("🔧 device     : \(UIDevice.current.model, privacy: .public)")
        #else
        log.notice("🔧 macOS      : \(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public)")
        log.notice("🔧 device     : \(Host.current().localizedName ?? "Mac", privacy: .public)")
        #endif

        // Entitlement probe — confirms whether the aps-environment key is
        // present in the signed binary. Missing = XPC crash on iOS 27.
        let entitlementsPath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision")
        log.notice("🔐 mobileprovision : \(entitlementsPath != nil ? "present" : "absent", privacy: .public)")

        // Model store snapshot
        let modelsDir = OnyxPaths.modelsDirectory()
        let activeFile = OnyxPaths.activeModelFile()
        let activeId = (try? String(contentsOf: activeFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "<none>"
        log.notice("📦 models dir : \(modelsDir.path, privacy: .public)")
        log.notice("📦 active id  : \(activeId, privacy: .public)")
    }
}
