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

// MARK: - OnyxTheme

/// Design tokens for the Onyx brand.
///
/// The adaptive accent (obsidian in light mode, silver in dark mode) is driven
/// by `AccentColor.colorset` in the asset catalog — reference it via
/// `Color.accentColor` or `.tint` as usual.
enum OnyxTheme {
    /// Silver gradient applied to the gem logo mark.
    static let gemGradient = LinearGradient(
        colors: [Color(white: 0.92), Color(white: 0.62)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Deep obsidian gradient used as the logo mark background.
    static let iconBackground = LinearGradient(
        colors: [
            Color(red: 0.07, green: 0.07, blue: 0.10),
            Color(red: 0.12, green: 0.12, blue: 0.17)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - OnyxLogoMark

/// The Onyx gem logo mark: a faceted diamond on a dark rounded-rect field.
///
/// Use at any size — defaults to 96 pt for the welcome screen.
struct OnyxLogoMark: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(OnyxTheme.iconBackground)
            DiamondShape()
                .fill(OnyxTheme.gemGradient)
                .frame(width: size * 0.52, height: size * 0.52)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - DiamondShape

/// A faceted cut-gem silhouette. The outline forms a classic brilliant-cut
/// diamond (8 crown + pavilion points). A horizontal table line across the
/// upper girdle adds the single facet detail that reads as a gemstone at small
/// display sizes.
private struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        // Outer silhouette (crown → pavilion → close)
        p.move(to:    CGPoint(x: w * 0.50, y: 0))          // top apex
        p.addLine(to: CGPoint(x: w * 0.80, y: h * 0.28))   // upper-right shoulder
        p.addLine(to: CGPoint(x: w * 1.00, y: h * 0.42))   // right girdle
        p.addLine(to: CGPoint(x: w * 0.80, y: h * 0.58))   // lower-right shoulder
        p.addLine(to: CGPoint(x: w * 0.50, y: h * 1.00))   // bottom culet
        p.addLine(to: CGPoint(x: w * 0.20, y: h * 0.58))   // lower-left shoulder
        p.addLine(to: CGPoint(x: w * 0.00, y: h * 0.42))   // left girdle
        p.addLine(to: CGPoint(x: w * 0.20, y: h * 0.28))   // upper-left shoulder
        p.closeSubpath()

        // Table line — horizontal facet across the crown
        p.move(to:    CGPoint(x: w * 0.20, y: h * 0.42))
        p.addLine(to: CGPoint(x: w * 0.80, y: h * 0.42))

        return p
    }
}

// MARK: - Preview

#Preview("OnyxLogoMark") {
    HStack(spacing: 20) {
        OnyxLogoMark(size: 60)
        OnyxLogoMark(size: 96)
        OnyxLogoMark(size: 128)
    }
    .padding()
    .background(Color.systemBackground)
}
