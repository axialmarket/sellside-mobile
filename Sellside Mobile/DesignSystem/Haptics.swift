//
//  Haptics.swift
//  Sellside Mobile
//

import UIKit

/// One-line haptic triggers so views don't juggle generators.
enum Haptics {
    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// For a segmented control or picker changing value — iOS doesn't do this
    /// one for you.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
