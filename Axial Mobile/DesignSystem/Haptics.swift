//
//  Haptics.swift
//  Axial Mobile
//

import UIKit

/// One-line haptic triggers so views don't juggle generators.
enum Haptics {
    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
