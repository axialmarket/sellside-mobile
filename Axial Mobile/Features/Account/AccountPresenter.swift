//
//  AccountPresenter.swift
//  Axial Mobile
//

import Foundation
import Observation

/// One page reachable from the Account sheet. Mirrors the two dropdowns on
/// fe-app `NavbarComponent` (navbar.component.html): "Profiles" (Member
/// Profile, Company Profile, Sign Out) and "Settings" (Notification
/// Settings, Company Settings, Add/Remove User, Get Help). Sign Out and Get
/// Help are actions rather than pages, so they aren't here.
enum AccountPage: String, Hashable, CaseIterable, Identifiable {
    case memberProfile      // /user/profile/info
    case companyProfile     // /company/:slug/view
    case notifications      // /user/notifications-settings
    case companySettings    // /company/settings
    case manageUsers        // /company/request-new-user

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memberProfile: "Member Profile"
        case .companyProfile: "Company Profile"
        case .notifications: "Notifications"
        case .companySettings: "Company Settings"
        case .manageUsers: "Add or Remove Users"
        }
    }

    var systemImage: String {
        switch self {
        case .memberProfile: "person"
        case .companyProfile: "building.2"
        case .notifications: "bell"
        case .companySettings: "gearshape"
        case .manageUsers: "person.2"
        }
    }

    /// The sheet's sections, in the web's order. Member Profile isn't
    /// listed here: the header card opens it, as the web's passport does.
    static let profiles: [AccountPage] = [.companyProfile]
    static let settings: [AccountPage] = [.notifications, .companySettings, .manageUsers]
}

/// Owns the Account sheet's presentation, so any screen can open it — at
/// the top, or straight onto one page — without owning a `.sheet` itself.
/// The sheet is attached once, above the navigation stack, in `ContentView`.
@Observable
final class AccountPresenter {
    var isPresented = false
    /// The sheet's own navigation stack. Opening onto a page seeds it, so
    /// Back still leads to the top of the sheet.
    var path: [AccountPage] = []

    /// Shared by the avatar button and the sheet for the zoom transition.
    static let transitionID = "account"

    func present(_ page: AccountPage? = nil) {
        path = page.map { [$0] } ?? []
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}

/// Initials for the avatar: the first letter of up to two words of the
/// name, uppercased. "A" for Axial when there's no name to work from.
enum AccountInitials {
    static func from(name: String?) -> String {
        let letters = (name ?? "").split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "A" : String(letters).uppercased()
    }
}
