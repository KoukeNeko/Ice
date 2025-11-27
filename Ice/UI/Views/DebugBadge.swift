//
//  DebugBadge.swift
//  Ice
//

import SwiftUI

/// A view that displays a badge indicating a debug/experimental feature.
struct DebugBadge: View {
    private var backgroundShape: some Shape {
        if #available(macOS 26.0, *) {
            Capsule(style: .continuous)
        } else {
            Capsule(style: .circular)
        }
    }

    var body: some View {
        Text("DEBUG")
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background {
                backgroundShape
                    .fill(.foreground.opacity(0.25))
            }
            .foregroundStyle(.orange)
    }
}
