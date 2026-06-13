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
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Platform-adaptive semantic colors
//
// Replace `Color(.systemBackground)` / `Color(.secondarySystemBackground)` /
// `Color(.separator)` — which expand to UIColor on iOS and fail to compile on
// macOS — with these named static properties that resolve to the correct
// platform type at compile time.

extension Color {
    /// Maps to `UIColor.systemBackground` (iOS) / `NSColor.windowBackgroundColor` (macOS).
    static var systemBackground: Color {
        #if os(iOS)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }

    /// Maps to `UIColor.secondarySystemBackground` (iOS) / `NSColor.controlBackgroundColor` (macOS).
    static var secondarySystemBackground: Color {
        #if os(iOS)
        Color(UIColor.secondarySystemBackground)
        #else
        Color(NSColor.controlBackgroundColor)
        #endif
    }

    /// Maps to `UIColor.separator` (iOS) / `NSColor.separatorColor` (macOS).
    static var systemSeparator: Color {
        #if os(iOS)
        Color(UIColor.separator)
        #else
        Color(NSColor.separatorColor)
        #endif
    }
}

// MARK: - Platform-adaptive toolbar placements
//
// `.topBarLeading` / `.topBarTrailing` are iOS 16+ only.
// On macOS, use `.navigation` (leading) and `.automatic` (trailing) instead.

extension ToolbarItemPlacement {
    /// Leading toolbar slot: `.topBarLeading` on iOS, `.navigation` on macOS.
    static var onyxLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    /// Trailing toolbar slot: `.topBarTrailing` on iOS, `.automatic` on macOS.
    static var onyxTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }
}

// MARK: - Platform-adaptive view modifiers

extension View {
    /// Applies `.navigationBarTitleDisplayMode(.inline)` on iOS; no-op on macOS.
    func navigationTitleInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Applies `.scrollDismissesKeyboard(.interactively)` on iOS; no-op on macOS.
    func dismissKeyboardOnScroll() -> some View {
        #if os(iOS)
        self.scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }
}
