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

import Foundation

// MARK: - Notification names

extension Notification.Name {
    static let ollamaServerSettingChanged = Notification.Name("onyx.ollamaServerSettingChanged")
    static let ollamaServerStatusChanged  = Notification.Name("onyx.ollamaServerStatusChanged")
}

// MARK: - Model name conversion

/// Converts a HuggingFace model ID to an Ollama-style name.
///
/// "mlx-community/Llama-3.2-1B-Instruct-4bit" → "llama3.2:1b-instruct-4bit"
/// "mlx-community/Qwen2.5-7B-Instruct-4bit"   → "qwen2.5:7b-instruct-4bit"
nonisolated func ollamaModelName(from hfId: String) -> String {
    let bare = hfId.split(separator: "/").last.map(String.init) ?? hfId
    let lower = bare.lowercased()
    let parts = lower.split(separator: "-").map(String.init)
    guard !parts.isEmpty else { return lower }

    // Find the first parameter-count token: digits (optionally ".N") followed by "b" or "m".
    // e.g. "1b", "7b", "70b", "1.5b", "8m"
    if let paramIdx = parts.firstIndex(where: _isParamCountToken) {
        let base = parts[..<paramIdx].joined()                  // "llama3.2"
        let tag  = parts[paramIdx...].joined(separator: "-")   // "1b-instruct-4bit"
        return tag.isEmpty ? base : "\(base):\(tag)"
    }

    // Fallback: first segment starting with a digit splits base from tag.
    if let vIdx = parts.firstIndex(where: { $0.first?.isNumber == true }), vIdx > 0 {
        let base = parts[..<(vIdx + 1)].joined()
        let rest = parts[(vIdx + 1)...].joined(separator: "-")
        return rest.isEmpty ? base : "\(base):\(rest)"
    }

    if parts.count > 1 {
        return "\(parts[0]):\(parts.dropFirst().joined(separator: "-"))"
    }
    return lower
}

nonisolated private func _isParamCountToken(_ s: String) -> Bool {
    guard s.hasSuffix("b") || s.hasSuffix("m") else { return false }
    let numeric = s.dropLast()
    return !numeric.isEmpty && numeric.allSatisfy { $0.isNumber || $0 == "." }
}

/// Extracts a human-readable parameter size from a HF model ID.
/// e.g. "mlx-community/Llama-3.2-1B-Instruct-4bit" → "1B"
nonisolated func extractParameterSize(from hfId: String) -> String {
    let bare = hfId.split(separator: "/").last.map(String.init) ?? hfId
    let parts = bare.lowercased().split(separator: "-").map(String.init)
    return parts.first(where: _isParamCountToken)?.uppercased() ?? "?"
}

/// Extracts a quantization-level string from a HF model ID.
/// e.g. "...-4bit" → "Q4_0"
nonisolated func extractQuantLevel(from hfId: String) -> String {
    let lower = hfId.lowercased()
    for n in ["8", "6", "5", "4", "3", "2"] {
        if lower.contains("\(n)bit") { return "Q\(n)_0" }
    }
    return "?"
}

// MARK: - Ollama native request types

struct OllamaChatRequest: Decodable, Sendable {
    let model: String
    let messages: [[String: String]]
    let stream: Bool?
}

struct OllamaGenerateRequest: Decodable, Sendable {
    let model: String
    let prompt: String
    let stream: Bool?
}

// MARK: - Ollama native response types

struct OllamaChatChunk: Encodable {
    let model: String
    let createdAt: String       // encoded as "created_at" via .convertToSnakeCase
    let message: OllamaMessage
    let done: Bool
    let doneReason: String?     // encoded as "done_reason"
}

struct OllamaMessage: Encodable {
    let role: String
    let content: String
}

struct OllamaGenerateChunk: Encodable {
    let model: String
    let createdAt: String
    let response: String
    let done: Bool
    let doneReason: String?
}

struct OllamaTagsResponse: Encodable {
    let models: [OllamaModelInfo]
}

struct OllamaModelInfo: Encodable {
    let name: String
    let model: String
    let modifiedAt: String
    let size: Int64
    let digest: String
    let details: OllamaModelDetails
}

struct OllamaModelDetails: Encodable {
    let format: String
    let family: String
    let families: [String]?
    let parameterSize: String
    let quantizationLevel: String
}

// MARK: - OpenAI-compatible request types

struct OpenAIChatRequest: Decodable, Sendable {
    let model: String
    let messages: [[String: String]]
    let stream: Bool?
}

// MARK: - OpenAI-compatible response types

struct OpenAIChatChunk: Encodable {
    let id: String
    let object: String          // "chat.completion.chunk"
    let created: Int
    let model: String
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Encodable {
    let index: Int
    let delta: OpenAIDelta
    let finishReason: String?   // encoded as "finish_reason"
}

struct OpenAIDelta: Encodable {
    let role: String?
    let content: String?
}

struct OpenAIModelsResponse: Encodable {
    let object: String
    let data: [OpenAIModelEntry]
}

struct OpenAIModelEntry: Encodable {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String         // encoded as "owned_by"
}

// MARK: - Shared error

enum OllamaServerError: Error, Sendable {
    case modelBusy
}
