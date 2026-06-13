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

// MARK: - ContentView
//
// PURPOSE: Root TabView. Two tabs:
//   1. Chat  — ChatView
//   2. Models — ModelsView
//
// TAB SWITCHING:
//   ChatView posts a `Notification.Name.switchToModelsTab` notification when
//   the user taps "Manage Models…" in the model picker. ContentView listens
//   for this and flips `selectedTab` to `.models`. This avoids tight coupling
//   between the two tab views.

/// Root view. Hosts the Chat and Models tabs.
///
/// This is the only view that knows about both tabs. All other views
/// communicate through actors, shared singletons, and notifications.
struct ContentView: View {

    private static let log = Logger(subsystem: "ai.kiraa.onyx", category: "Lifecycle")

    // MARK: - AppTab enum

    enum AppTab: Hashable {
        case chat
        case models
        case settings
    }

    @State private var selectedTab: AppTab = .chat

    var body: some View {
        let _ = Self.log.notice("🟢 ContentView.body evaluated")
        return TabView(selection: $selectedTab) {
            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag(AppTab.chat)
                .onAppear { Self.log.notice("🗂 ChatView appeared") }
            ModelsView()
                .tabItem { Label("Models", systemImage: "square.stack.3d.up") }
                .tag(AppTab.models)
                .onAppear { Self.log.notice("🗂 ModelsView appeared") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
                .onAppear { Self.log.notice("🗂 SettingsView appeared") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToModelsTab)) { _ in
            selectedTab = .models
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification
        )) { _ in
            Self.log.warning("⚠️ memory warning — cancelling generation and unloading model")
            ChatProvider.shared.cancel()
            Task { await MLXModelManager.shared.unloadModel() }
        }
        #endif
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
