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
import Network
import os.log

// MARK: - OllamaServer

/// Actor that runs a minimal HTTP/1.1 server on localhost speaking the Ollama REST API.
///
/// Endpoints:
///   GET  /                        → version JSON
///   GET  /api/version             → version JSON
///   GET  /api/tags                → installed models in Ollama format
///   POST /api/chat                → streaming NDJSON chat
///   POST /api/generate            → streaming NDJSON generate
///   GET  /v1/models               → installed models in OpenAI format
///   POST /v1/chat/completions     → streaming SSE chat (OpenAI format)
///
/// Start/stop are controlled by OnyxSettings.ollamaServerEnabled via OnyxApp.
actor OllamaServer {

    static let shared = OllamaServer()

    private var listener: NWListener?
    private let log = Logger(subsystem: "ai.kiraa.onyx", category: "OllamaServer")

    private init() {}

    // MARK: - Lifecycle

    /// Start the server on `port`. No-op if already running.
    func start(port: UInt16 = 11434) throws {
        guard listener == nil else { return }
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: nwPort)
        l.newConnectionHandler = { [weak self] conn in
            Task { await self?.handleConnection(conn) }
        }
        l.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleListenerState(state) }
        }
        l.start(queue: .global(qos: .userInitiated))
        listener = l
        log.notice("OllamaServer starting on :\(port)")
    }

    /// Stop the server and close the listening socket.
    func stop() {
        listener?.cancel()
        listener = nil
        log.notice("OllamaServer stopped")
        NotificationCenter.default.post(name: .ollamaServerStatusChanged, object: false)
    }

    /// Whether the listener is currently open.
    var isRunning: Bool { listener != nil }

    // MARK: - Listener state

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            log.notice("OllamaServer ready")
            NotificationCenter.default.post(name: .ollamaServerStatusChanged, object: true)
        case .failed(let error):
            log.error("OllamaServer listener failed: \(error)")
            listener = nil
            // Reset the setting so the toggle in Settings reflects reality.
            Task { @MainActor in
                OnyxSettings.shared.ollamaServerEnabled = false
            }
            NotificationCenter.default.post(name: .ollamaServerStatusChanged, object: false)
        case .cancelled:
            NotificationCenter.default.post(name: .ollamaServerStatusChanged, object: false)
        default:
            break
        }
    }

    // MARK: - Connection handling

    private func handleConnection(_ conn: NWConnection) async {
        conn.start(queue: .global(qos: .userInitiated))
        defer { conn.cancel() }
        do {
            guard let request = try await receiveHTTPRequest(conn) else { return }
            await route(request: request, connection: conn)
        } catch {
            log.debug("OllamaServer connection error: \(error)")
        }
    }

    // MARK: - HTTP receive

    private func receiveHTTPRequest(_ conn: NWConnection) async throws -> HTTPRequest? {
        var accumulated = Data()
        let sep = Data([0x0D, 0x0A, 0x0D, 0x0A])  // \r\n\r\n

        while true {
            let (chunk, isComplete) = try await withCheckedThrowingContinuation {
                (cont: CheckedContinuation<(Data, Bool), Error>) in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                    data, _, complete, error in
                    if let error { cont.resume(throwing: error); return }
                    cont.resume(returning: (data ?? Data(), complete))
                }
            }
            accumulated.append(chunk)

            guard let sepRange = accumulated.range(of: sep) else {
                if isComplete { return HTTPRequest(data: accumulated) }
                continue
            }

            let headerStr = String(data: accumulated[..<sepRange.lowerBound],
                                   encoding: .utf8) ?? ""
            let contentLength = _parseContentLength(from: headerStr)
            let bodyReceived  = accumulated.count - sepRange.upperBound

            if bodyReceived >= contentLength { return HTTPRequest(data: accumulated) }
            if isComplete { return HTTPRequest(data: accumulated) }
        }
    }

    // MARK: - Router

    private func route(request: HTTPRequest, connection: NWConnection) async {
        if request.method == "OPTIONS" {
            await sendCORSPreflight(connection)
            return
        }
        switch (request.method, request.path) {
        case ("GET", "/"), ("GET", "/api/version"):
            await sendJSON(connection, status: 200, body: #"{"version":"0.1.0"}"#)
        case ("GET", "/api/tags"):
            await handleTags(connection)
        case ("POST", "/api/chat"):
            await handleChat(request: request, connection: connection)
        case ("POST", "/api/generate"):
            await handleGenerate(request: request, connection: connection)
        case ("GET", "/v1/models"):
            await handleOpenAIModels(connection)
        case ("POST", "/v1/chat/completions"):
            await handleOpenAIChat(request: request, connection: connection)
        default:
            await sendJSON(connection, status: 404, body: #"{"error":"not found"}"#)
        }
    }

    // MARK: - Ollama handlers

    private func handleTags(_ conn: NWConnection) async {
        let installed = await ChatModelRegistry.shared.installedIds()
        let activeId  = await ChatModelRegistry.shared.activeId()

        var infos: [OllamaModelInfo] = installed.map { id in
            let desc = ChatModelCatalog.descriptor(forId: id)
            return OllamaModelInfo(
                name: ollamaModelName(from: id),
                model: ollamaModelName(from: id),
                modifiedAt: "1970-01-01T00:00:00Z",
                size: desc?.approxSizeBytes ?? 0,
                digest: "sha256:onyx",
                details: OllamaModelDetails(
                    format: "gguf",
                    family: desc?.family.rawValue ?? "other",
                    families: nil,
                    parameterSize: extractParameterSize(from: id),
                    quantizationLevel: extractQuantLevel(from: id)
                )
            )
        }

        if let activeId {
            let activeName = ollamaModelName(from: activeId)
            infos.sort { $0.name == activeName && $1.name != activeName }
        }

        let enc = makeEncoder()
        if let data = try? enc.encode(OllamaTagsResponse(models: infos)) {
            await sendResponse(conn, status: 200, contentType: "application/json", body: data)
        }
    }

    private func handleChat(request: HTTPRequest, connection: NWConnection) async {
        guard let req = try? JSONDecoder().decode(OllamaChatRequest.self,
                                                  from: request.body) else {
            await sendJSON(connection, status: 400,
                          body: #"{"error":"invalid request body"}"#)
            return
        }
        await streamOllama(messages: req.messages, connection: connection, isChat: true)
    }

    private func handleGenerate(request: HTTPRequest, connection: NWConnection) async {
        guard let req = try? JSONDecoder().decode(OllamaGenerateRequest.self,
                                                  from: request.body) else {
            await sendJSON(connection, status: 400,
                          body: #"{"error":"invalid request body"}"#)
            return
        }
        let messages = [["role": "user", "content": req.prompt]]
        await streamOllama(messages: messages, connection: connection, isChat: false)
    }

    private func streamOllama(
        messages: [[String: String]],
        connection: NWConnection,
        isChat: Bool
    ) async {
        let stream: AsyncStream<String>
        do {
            stream = try await ChatProvider.shared.respondDirect(messages: messages)
        } catch OllamaServerError.modelBusy {
            await sendJSON(connection, status: 503, body: #"{"error":"model busy"}"#)
            return
        } catch {
            let msg = sanitize(error.localizedDescription)
            await sendJSON(connection, status: 503,
                          body: "{\"error\":\"\(msg)\"}")
            return
        }

        let modelName = await currentOllamaModelName()
        let now = ISO8601DateFormatter().string(from: Date())
        let enc = makeEncoder()

        await sendStreamingHeaders(connection, contentType: "application/x-ndjson")

        for await token in stream {
            let data: Data?
            if isChat {
                data = try? enc.encode(OllamaChatChunk(
                    model: modelName, createdAt: now,
                    message: OllamaMessage(role: "assistant", content: token),
                    done: false, doneReason: nil))
            } else {
                data = try? enc.encode(OllamaGenerateChunk(
                    model: modelName, createdAt: now,
                    response: token, done: false, doneReason: nil))
            }
            if var line = data {
                line.append(0x0A)
                guard await sendRaw(connection, data: line) else { break }
            }
        }

        let finalData: Data?
        if isChat {
            finalData = try? enc.encode(OllamaChatChunk(
                model: modelName, createdAt: now,
                message: OllamaMessage(role: "assistant", content: ""),
                done: true, doneReason: "stop"))
        } else {
            finalData = try? enc.encode(OllamaGenerateChunk(
                model: modelName, createdAt: now,
                response: "", done: true, doneReason: "stop"))
        }
        if var line = finalData { line.append(0x0A); await sendRaw(connection, data: line) }
    }

    // MARK: - OpenAI-compatible handlers

    private func handleOpenAIModels(_ conn: NWConnection) async {
        let installed = await ChatModelRegistry.shared.installedIds()
        let entries = installed.map {
            OpenAIModelEntry(id: ollamaModelName(from: $0), object: "model",
                             created: 0, ownedBy: "onyx")
        }
        let enc = makeEncoder()
        if let data = try? enc.encode(OpenAIModelsResponse(object: "list", data: entries)) {
            await sendResponse(conn, status: 200, contentType: "application/json", body: data)
        }
    }

    private func handleOpenAIChat(request: HTTPRequest, connection: NWConnection) async {
        guard let req = try? JSONDecoder().decode(OpenAIChatRequest.self,
                                                  from: request.body) else {
            await sendJSON(connection, status: 400,
                          body: #"{"error":{"message":"invalid request body","type":"invalid_request_error"}}"#)
            return
        }

        let stream: AsyncStream<String>
        do {
            stream = try await ChatProvider.shared.respondDirect(messages: req.messages)
        } catch OllamaServerError.modelBusy {
            await sendJSON(connection, status: 503,
                          body: #"{"error":{"message":"model busy","type":"server_error"}}"#)
            return
        } catch {
            let msg = sanitize(error.localizedDescription)
            await sendJSON(connection, status: 503,
                          body: "{\"error\":{\"message\":\"\(msg)\",\"type\":\"server_error\"}}")
            return
        }

        let modelName = await currentOllamaModelName()
        let chatId    = "onyx-\(Int(Date().timeIntervalSince1970))"
        let created   = Int(Date().timeIntervalSince1970)
        let enc       = makeEncoder()

        await sendStreamingHeaders(connection, contentType: "text/event-stream")

        // First chunk carries the role
        if let data = try? enc.encode(OpenAIChatChunk(
            id: chatId, object: "chat.completion.chunk", created: created, model: modelName,
            choices: [OpenAIChoice(
                index: 0,
                delta: OpenAIDelta(role: "assistant", content: ""),
                finishReason: nil)])) {
            await sendSSELine(connection, data: data)
        }

        for await token in stream {
            if let data = try? enc.encode(OpenAIChatChunk(
                id: chatId, object: "chat.completion.chunk", created: created, model: modelName,
                choices: [OpenAIChoice(
                    index: 0,
                    delta: OpenAIDelta(role: nil, content: token),
                    finishReason: nil)])) {
                guard await sendSSELine(connection, data: data) else { break }
            }
        }

        // Final chunk with finish_reason
        if let data = try? enc.encode(OpenAIChatChunk(
            id: chatId, object: "chat.completion.chunk", created: created, model: modelName,
            choices: [OpenAIChoice(
                index: 0,
                delta: OpenAIDelta(role: nil, content: nil),
                finishReason: "stop")])) {
            await sendSSELine(connection, data: data)
        }

        await sendRaw(connection, data: Data("data: [DONE]\n\n".utf8))
    }

    // MARK: - Shared helpers

    private func currentOllamaModelName() async -> String {
        let id = await ChatModelRegistry.shared.activeId() ?? "unknown"
        return ollamaModelName(from: id)
    }

    private func makeEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        return enc
    }

    // MARK: - Response writing

    private func sendCORSPreflight(_ conn: NWConnection) async {
        let header = "HTTP/1.1 204 No Content\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" +
            "Access-Control-Allow-Headers: Content-Type, Authorization\r\n" +
            "Access-Control-Max-Age: 86400\r\n" +
            "Content-Length: 0\r\n" +
            "Connection: close\r\n\r\n"
        await sendRaw(conn, data: Data(header.utf8))
    }

    private func sendStreamingHeaders(_ conn: NWConnection, contentType: String) async {
        let h = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
        await sendRaw(conn, data: Data(h.utf8))
    }

    @discardableResult
    private func sendSSELine(_ conn: NWConnection, data: Data) async -> Bool {
        var line = Data("data: ".utf8)
        line.append(data)
        line.append(Data("\n\n".utf8))
        return await sendRaw(conn, data: line)
    }

    private func sendJSON(_ conn: NWConnection, status: Int, body: String) async {
        await sendResponse(conn, status: status, contentType: "application/json",
                          body: Data(body.utf8))
    }

    private func sendResponse(_ conn: NWConnection, status: Int,
                               contentType: String = "application/json",
                               body: Data) async {
        let statusText = _httpStatusText(status)
        let header = "HTTP/1.1 \(status) \(statusText)\r\n" +
            "Content-Type: \(contentType); charset=utf-8\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n" +
            "Access-Control-Allow-Origin: *\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        await sendRaw(conn, data: response)
    }

    @discardableResult
    private func sendRaw(_ conn: NWConnection, data: Data) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            conn.send(content: data, completion: .contentProcessed { error in
                cont.resume(returning: error == nil)
            })
        }
    }
}

// MARK: - HTTPRequest

private struct HTTPRequest {
    let method: String
    let path: String
    let body: Data

    init?(data: Data) {
        let sep = Data([0x0D, 0x0A, 0x0D, 0x0A])
        if let sepRange = data.range(of: sep) {
            let headerStr = String(data: data[..<sepRange.lowerBound], encoding: .utf8) ?? ""
            guard let (m, p) = Self.parseRequestLine(headerStr) else { return nil }
            method = m; path = p
            body = Data(data[sepRange.upperBound...])
        } else {
            let headerStr = String(data: data, encoding: .utf8) ?? ""
            guard let (m, p) = Self.parseRequestLine(headerStr) else { return nil }
            method = m; path = p; body = Data()
        }
    }

    private static func parseRequestLine(_ raw: String) -> (String, String)? {
        guard let firstLine = raw.components(separatedBy: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}

// MARK: - File-level helpers (nonisolated required by SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor)

nonisolated private func _parseContentLength(from headers: String) -> Int {
    for line in headers.components(separatedBy: "\r\n") {
        guard line.lowercased().hasPrefix("content-length:") else { continue }
        let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
        return Int(value) ?? 0
    }
    return 0
}

nonisolated private func _httpStatusText(_ code: Int) -> String {
    switch code {
    case 200: return "OK"
    case 400: return "Bad Request"
    case 404: return "Not Found"
    case 500: return "Internal Server Error"
    case 503: return "Service Unavailable"
    default:  return "Unknown"
    }
}

nonisolated private func sanitize(_ msg: String) -> String {
    String(msg.prefix(200)).replacingOccurrences(of: "\"", with: "'")
}
