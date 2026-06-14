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

struct SettingsView: View {

    @State private var systemPromptDraft: String = ChatProvider.shared.systemPrompt
    @State private var showCacheClearConfirm = false
    @State private var serverIsRunning = false

    var body: some View {
        NavigationStack {
            Form {
                assistantSection
                serverSection
                developerSection
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
        .task {
            serverIsRunning = await OllamaServer.shared.isRunning
        }
        .onReceive(NotificationCenter.default.publisher(for: .ollamaServerStatusChanged)) { n in
            serverIsRunning = n.object as? Bool ?? false
        }
        .onDisappear {
            ChatProvider.shared.systemPrompt = systemPromptDraft
        }
    }

    private var assistantSection: some View {
        Section {
            TextEditor(text: $systemPromptDraft)
                .font(.body)
                .frame(minHeight: 120)
            Button("Reset to Default") {
                systemPromptDraft = ChatProvider.defaultSystemPrompt
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text("Assistant")
        } footer: {
            Text("Injected before every conversation. Changes take effect on the next message.")
        }
    }

    private var serverSection: some View {
        Section {
            Toggle("Enable Ollama API Server", isOn: Binding(
                get: { OnyxSettings.shared.ollamaServerEnabled },
                set: { newValue in
                    OnyxSettings.shared.ollamaServerEnabled = newValue
                    NotificationCenter.default.post(
                        name: .ollamaServerSettingChanged, object: nil)
                }
            ))
            if OnyxSettings.shared.ollamaServerEnabled {
                HStack {
                    Text("Port")
                    Spacer()
                    Text("\(OnyxSettings.shared.ollamaServerPort)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Status")
                    Spacer()
                    Text(serverIsRunning ? "Running" : "Starting…")
                        .foregroundStyle(serverIsRunning ? .green : .secondary)
                }
            }
        } header: {
            Text("Local AI Server")
        } footer: {
            Text("Exposes an Ollama-compatible API on localhost:\(OnyxSettings.shared.ollamaServerPort). Connect Open WebUI or any Ollama/OpenAI client to http://localhost:\(OnyxSettings.shared.ollamaServerPort).")
        }
    }

    private var developerSection: some View {
        Section {
            Button(role: .destructive) {
                showCacheClearConfirm = true
            } label: {
                Label("Clear Incomplete Downloads", systemImage: "trash")
            }
            .confirmationDialog(
                "Clear incomplete downloads?",
                isPresented: $showCacheClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear", role: .destructive) {
                    Task { await ChatModelDownloader.shared.clearCache() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes partially-downloaded files from the cache. Completed model installs are not affected.")
            }
        } header: {
            Text("Developer")
        }
    }
}

#Preview {
    SettingsView()
}
