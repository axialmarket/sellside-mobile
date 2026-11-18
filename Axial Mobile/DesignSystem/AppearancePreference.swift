//
//  AppearancePreference.swift
//  Axial Mobile
//

import SwiftUI
import UIKit

/// Light, Dark, or follow the system — the Account sheet's Appearance
/// setting. Stored in `UserDefaults` under `storageKey`; it's a device
/// preference, not account data.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// What the windows are told to use. `.unspecified` hands the decision
    /// back to the system setting.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

extension View {
    /// Applies the stored appearance to every window of the app.
    ///
    /// Set on the windows rather than with `.preferredColorScheme`, which
    /// only reaches the presentation it's attached to — sheets would keep
    /// the old appearance until reopened. A window's style covers its sheets,
    /// alerts and menus too. The switch cross-fades, unless Reduce Motion is
    /// on.
    func appearancePreference(_ preference: AppearancePreference) -> some View {
        modifier(AppearanceApplier(preference: preference))
    }
}

private struct AppearanceApplier: ViewModifier {
    let preference: AppearancePreference

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onAppear { apply(animated: false) }
            .onChange(of: preference) { _, _ in apply(animated: !reduceMotion) }
    }

    private func apply(animated: Bool) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows {
            guard window.overrideUserInterfaceStyle != preference.interfaceStyle else { continue }
            if animated {
                UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
                    window.overrideUserInterfaceStyle = preference.interfaceStyle
                }
            } else {
                window.overrideUserInterfaceStyle = preference.interfaceStyle
            }
        }
    }
}
