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

// MARK: - Block model

private enum MDBlock {
    case paragraph(String)
    case heading(level: Int, text: String)
    case code(lang: String?, body: String)
    case bulletList([String])
    case orderedList([String])
}

// MARK: - Parser

private enum MDParser {

    static func parse(_ raw: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = raw.components(separatedBy: "\n")
        var i = lines.startIndex

        while i < lines.endIndex {
            let line = lines[i]

            // ── Fenced code block ───────────────────────────────────────────
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var body: [String] = []
                while i < lines.endIndex && !lines[i].hasPrefix("```") {
                    body.append(lines[i])
                    i += 1
                }
                if i < lines.endIndex { i += 1 } // consume closing fence
                blocks.append(.code(
                    lang: lang.isEmpty ? nil : lang,
                    body: body.joined(separator: "\n")
                ))
                continue
            }

            // ── ATX heading ─────────────────────────────────────────────────
            if let (level, text) = heading(line) {
                blocks.append(.heading(level: level, text: text))
                i += 1
                continue
            }

            // ── Unordered list ──────────────────────────────────────────────
            if bulletPrefix(line) != nil {
                var items: [String] = []
                while i < lines.endIndex, let pfx = bulletPrefix(lines[i]) {
                    items.append(String(lines[i].dropFirst(pfx)))
                    i += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            // ── Ordered list ────────────────────────────────────────────────
            if let drop = orderedPrefix(line) {
                var items: [String] = []
                while i < lines.endIndex, let d = orderedPrefix(lines[i]) {
                    items.append(String(lines[i].dropFirst(d)))
                    i += 1
                }
                _ = drop
                blocks.append(.orderedList(items))
                continue
            }

            // ── Blank line (paragraph separator) ───────────────────────────
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // ── Paragraph ───────────────────────────────────────────────────
            var paraLines: [String] = []
            while i < lines.endIndex {
                let l = lines[i]
                if l.hasPrefix("```") || heading(l) != nil
                    || bulletPrefix(l) != nil || orderedPrefix(l) != nil { break }
                if l.trimmingCharacters(in: .whitespaces).isEmpty { i += 1; break }
                paraLines.append(l)
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(paraLines.joined(separator: "\n")))
            }
        }

        return blocks
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    private static func heading(_ line: String) -> (Int, String)? {
        for (pfx, level) in [("#### ", 4), ("### ", 3), ("## ", 2), ("# ", 1)] {
            if line.hasPrefix(pfx) { return (level, String(line.dropFirst(pfx.count))) }
        }
        return nil
    }

    /// Returns prefix character count to drop, or nil.
    private static func bulletPrefix(_ line: String) -> Int? {
        for pfx in ["- ", "* ", "+ "] {
            if line.hasPrefix(pfx) { return pfx.count }
        }
        return nil
    }

    /// Returns prefix character count to drop for "N. " patterns, or nil.
    private static func orderedPrefix(_ line: String) -> Int? {
        var idx = line.startIndex
        while idx < line.endIndex && line[idx].isNumber {
            idx = line.index(after: idx)
        }
        guard idx > line.startIndex,
              idx < line.endIndex, line[idx] == "." else { return nil }
        let afterDot = line.index(after: idx)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return line.distance(from: line.startIndex, to: afterDot) + 1
    }
}

// MARK: - MarkdownMessageView

/// Renders a full-Markdown assistant message with proper block formatting.
///
/// Block types: fenced code blocks, ATX headings, bullet/ordered lists,
/// paragraphs. Inline Markdown (bold, italic, `code`) is applied within each
/// block. Link attributes are stripped to prevent tappable model-injected URLs.
struct MarkdownMessageView: View {

    let text: String

    var body: some View {
        let blocks = MDParser.parse(sanitized(text))
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Block renderers

    @ViewBuilder
    private func blockView(for block: MDBlock) -> some View {
        switch block {
        case .paragraph(let raw):
            inlineText(raw)

        case .heading(let level, let raw):
            inlineText(raw)
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 2 : 0)

        case .code(let lang, let body):
            MDCodeBlockView(lang: lang, code: body)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        inlineText(item)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(i + 1).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 20, alignment: .trailing)
                        inlineText(item)
                    }
                }
            }
        }
    }

    // MARK: - Inline Markdown

    private func inlineText(_ raw: String) -> some View {
        Text(inlineAttributed(raw))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func inlineAttributed(_ raw: String) -> AttributedString {
        var a = (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(raw)
        let linkRanges = a.runs.filter { $0.link != nil }.map(\.range)
        for range in linkRanges { a[range].link = nil }
        return a
    }

    // MARK: - Helpers

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .title3.bold()
        case 3: return .headline
        default: return .subheadline.bold()
        }
    }

    private func sanitized(_ text: String) -> String {
        text.filter { ch in
            guard ch.isASCII, let v = ch.asciiValue else { return true }
            return v >= 0x20 || v == 0x09 || v == 0x0A || v == 0x0D
        }
    }
}

// MARK: - Code block view

private struct MDCodeBlockView: View {
    let lang: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lang {
                Text(lang)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            Divider().opacity(lang != nil ? 1 : 0)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(.caption, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.tertiarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.systemSeparator, lineWidth: 0.5)
        )
    }
}

// MARK: - Preview

#Preview("Markdown rendering") {
    ScrollView {
        MarkdownMessageView(text: """
        Here's a **bold** claim and some _italic_ text with `inline code`.

        ## Code example

        ```swift
        func greet(_ name: String) -> String {
            return "Hello, \\(name)!"
        }
        ```

        ### Steps

        - First item
        - Second item with **emphasis**
        - Third

        1. Download the model
        2. Activate it
        3. Start chatting

        Plain paragraph at the end.
        """)
        .padding()
    }
}
