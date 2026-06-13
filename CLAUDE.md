# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Onyx is a multiplatform on-device LLM chat app (iOS + macOS native) built on Apple's MLX framework. Forked from kiraa-ai/project-onyx. Ships minimal: one model, no accounts, no API keys, no persistence.

- **Xcode project**: `Onyx/Onyx.xcodeproj`
- **iOS bundle id**: `com.litusmar.onyx` | **macOS bundle id**: `com.litusmar.onyx.mac`
- **App version**: 0.1 (beta)
- **Deployment targets**: iOS 17.0+ / macOS 14.0+
- **Swift packages**: `mlx-swift-lm` (3.31.3+) and `swift-transformers` (1.3.0+), both resolved remotely
- **iOS entitlements**: `com.apple.developer.kernel.increased-memory-limit`
- **macOS entitlements**: `app-sandbox` + `network.client` + `files.user-selected.read-write` (in `mac/mac.entitlements`)
- **Known issue**: iOS 27 beta is NOT supported — crashes pre-main. Supported: iOS 17–26.

## Multiplatform architecture

Platform-specific code is isolated in `Onyx/Onyx/Design/PlatformAdaptations.swift`:
- `Color.systemBackground`, `.secondarySystemBackground`, `.tertiarySystemBackground`, `.systemSeparator` — adaptive UIColor/NSColor wrappers
- `ToolbarItemPlacement.onyxLeading` / `.onyxTrailing` — `.topBarLeading/Trailing` on iOS, `.navigation/.automatic` on macOS
- `View.navigationTitleInline()` / `.dismissKeyboardOnScroll()` — iOS-only modifiers, no-op on macOS

`MessageBubble` uses `@Environment(\.colorScheme)` to pick contrasting text on the accent bubble (the accent inverts light/dark: obsidian in light mode, silver in dark mode).

## Build commands

```bash
# Resolve packages + build for simulator (no inference, but UI compiles)
xcodebuild -project Onyx/Onyx.xcodeproj -scheme Onyx \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -resolvePackageDependencies

xcodebuild build -project Onyx/Onyx.xcodeproj -scheme Onyx \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Download-progress UI test (downloads the real 860 MB model; delete the app's
# Models directory in the simulator container first so the Download button exists)
xcodebuild test -project Onyx/Onyx.xcodeproj -scheme Onyx \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:OnyxUITests/OnyxUITests/testDownloadProgressMovesRegularly \
  -parallel-testing-enabled NO

# Actual inference requires a physical iPhone 15+ (Metal GPU).
# Model downloads DO work in the simulator; only chat inference does not.
```

## Architecture

All Swift source files are in `Onyx/Onyx/` and are picked up automatically by Xcode's `PBXFileSystemSynchronizedRootGroup` — **no pbxproj changes are needed when adding new `.swift` files**.

**Layer order** (bottom → top):

| Layer | Files | Notes |
|---|---|---|
| Runtime | `OnyxPaths`, `MLXErrors`, `MLXModelManager`, `MLXConversationHistory` | Actors; no SwiftUI |
| Download | `ChatModelDownloader`, `ChatModelCatalog`, `ChatModelRegistry` | Actors; HF Hub |
| Gate | `HardwareProfile`, `ChatMemoryGate` | nonisolated helpers |
| Settings | `OnyxSettings` | @MainActor @Observable singleton; UserDefaults only |
| Provider | `ChatProvider` | @MainActor @Observable |
| Views | `ChatView`, `ModelsView`, `PreferencesView` (defines `SettingsView`), `MessageBubble`, `DownloadRow`, `ThinkingDotsView` | SwiftUI |
| Entry | `OnyxApp`, `ContentView` | @main; TabView with Chat / Models / Settings tabs |

## Critical build settings

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — **every unannotated function is `@MainActor`**. Any function that must run off the main thread (e.g. `generateFromModel`) must be explicitly `nonisolated`.
- `IPHONEOS_DEPLOYMENT_TARGET = 17.0` — required for `@Observable`, `AsyncStream`, and MLX.
- `com.apple.developer.kernel.increased-memory-limit` entitlement — allows the model to stay resident on 6 GB devices. Do not add other entitlements; unused ones are suspected in the iOS 27 pre-main crash.

## Memory management

The app unloads the resident model when backgrounded (`OnyxApp.onChange(scenePhase == .background)`) and on low-memory warnings (`ContentView.onReceive(UIApplication.didReceiveMemoryWarningNotification)`). The model reloads lazily on the next chat turn. This prevents JetSam kills on 6 GB iPhones.

## Model catalog

`ChatModelCatalog.all` ships with exactly one model: `mlx-community/Llama-3.2-1B-Instruct-4bit` (≈ 860 MB). Models too large for the current device's RAM (checked via `HardwareProfile.canLoadModel(approxSizeBytes:)`) show an orange "Requires more RAM" badge but are not blocked from downloading. Downloads are public — no HuggingFace token anywhere in the app.

To add a model: append a `ChatModelDescriptor` to `ChatModelCatalog.all` in `ChatModelCatalog.swift`. No other changes needed. `family` is `.llama` or `.other`.

## Download pipeline & progress

`ChatModelDownloader` runs a 5-phase pipeline: resolving → preparing → downloading → verifying → done/failed/cancelled. The model **auto-activates** when a download completes (`DownloadRow` calls `onActivate` on `phase == .done`).

Progress reporting uses two sources because `HubApi.snapshot`'s callbacks can go silent for 60–90 s mid-transfer:
1. HubApi progress callbacks (coarse, bursty)
2. A 1 Hz **disk poller** (`bytesOnDisk`) that measures real byte growth in the download cache + tmp directory

`emitProgress` takes the max of both and is monotonic (never goes backwards). `State.overallFraction` maps the whole pipeline onto one bar: resolving 3% → preparing 8% → downloading 10–95% → verifying 97% → done 100%. `DownloadRow` smooths rendering with a 4 Hz ticker (`displayedFraction`) that eases toward the real fraction and creeps slightly (capped +2%, never past 95%) so the bar never visibly stops. `OnyxUITests/testDownloadProgressMovesRegularly` guards this behaviour.

## Key API patterns

```swift
// Load and generate (from any @MainActor context)
let stream = try await ChatProvider.shared.respond(to: "Hello")
for await chunk in stream { /* update UI */ }

// Download a model (public, no token)
try await ChatModelDownloader.shared.start(
    modelId: "mlx-community/...",
    revision: "main",
    matching: descriptor.filePatterns,
    installPath: OnyxPaths.modelDirectory(for: descriptor.id),
    approxSizeBytes: descriptor.approxSizeBytes
)

// Subscribe to download progress (auto-activation happens in DownloadRow when phase == .done)
let stream = await ChatModelDownloader.shared.subscribe(id: modelId)

// Activate a model
try await ChatModelRegistry.shared.setActive("mlx-community/...")
```

## Storage

| What | Where | Owner |
|---|---|---|
| `onyx.systemPrompt` | UserDefaults | `ChatProvider.systemPrompt` |
| `onyx.logPrompts` | UserDefaults | `OnyxSettings.logPrompts` |
| Active model id | `<AppSupport>/Onyx/Models/active.txt` | `ChatModelRegistry` |
| Model weights | `<AppSupport>/Onyx/Models/<repo-id>/` | `ChatModelRegistry` / `ChatModelDownloader` |
| Download cache (resumable) | `<AppSupport>/Onyx/Models/.cache/` | `ChatModelDownloader` |

No Keychain, no SwiftData, no CoreData. Conversations are in-memory only (reset on restart). To add persistence, encode `MLXConversationHistory.turns` to JSON and write to `OnyxPaths.baseDirectory()`.

## Debug logging

- Outgoing prompts: stdout, look for `📨 [Onyx]`. Disable with `OnyxSettings.shared.logPrompts = false`.
- Download pipeline: os.log subsystem `ai.chatmlx.download` and an on-device file at `<AppSupport>/Onyx/Models/.cache/download-log.txt`.
- App lifecycle: os.log subsystem `ai.kiraa.onyx` (category `Lifecycle`). `OnyxApp.init` also appends a boot stamp to `Documents/boot-stamp.txt` — if that file is missing after a launch attempt, the crash happened pre-main (used for the iOS 27 investigation).
