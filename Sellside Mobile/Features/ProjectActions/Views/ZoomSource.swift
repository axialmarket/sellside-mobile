//
//  ZoomSource.swift
//  Sellside Mobile
//

import SwiftUI

/// Where a sheet zooms out of: a namespace and an id within it.
struct ZoomSource {
    let namespace: Namespace.ID
    let id: String
}

extension View {
    /// Marks a view as the source a sheet zooms out of and collapses back
    /// into, when there is one. Content only — a bar item needs the
    /// `ToolbarContent` overload on the `ToolbarItem` (CLAUDE.md).
    ///
    /// Anchor it to an opaque surface, never a glass button. The zoom ends
    /// on the source's frame, clipped to `shape` and filled with
    /// `background`. A capsule glass button gives it a square frame around
    /// a rounded lens, which redraws its own glass underneath as the sheet
    /// lands, and that showed as an artifact on collapse. A card or row
    /// with a matching shape and fill gives it something solid to land on.
    /// The transition only clips to a `RoundedRectangle`, all four corners
    /// alike.
    @ViewBuilder
    func zoomSource(id: String, in namespace: Namespace.ID?,
                    cornerRadius: CGFloat, background: Color = AxialColor.surface) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace) { source in
                source
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .background(background)
            }
        } else {
            self
        }
    }

    /// The presented side of `zoomSource`. Without a source it's the plain
    /// sheet slide; under Reduce Motion the system cross-fades on its own.
    @ViewBuilder
    func zooming(from source: ZoomSource?) -> some View {
        if let source {
            navigationTransition(.zoom(sourceID: source.id, in: source.namespace))
        } else {
            self
        }
    }
}
