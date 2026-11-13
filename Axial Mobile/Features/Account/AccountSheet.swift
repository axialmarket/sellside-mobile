//
//  AccountSheet.swift
//  Axial Mobile
//

import SwiftUI
import Auth0

/// Profiles, settings and sign-out — the mobile form of the web's
/// "Profiles" and "Settings" navbar dropdowns (fe-app navbar.component.html).
/// Presented by `AccountPresenter` from anywhere in the app.
struct AccountSheet: View {
    @Environment(AccountPresenter.self) private var presenter
    @Environment(AuthenticationService.self) private var authService

    /// The web's `EXT_URL.help` (settings.constants.ts). The web opens a
    /// Document360 widget and falls back to email; the widget is web-only,
    /// so mobile goes to the guide it's built on.
    private static let helpURL = URL(string: "https://guide.axial.net/")!

    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .system

    var body: some View {
        @Bindable var presenter = presenter
        NavigationStack(path: $presenter.path) {
            List {
                Section {
                    NavigationLink(value: AccountPage.memberProfile) { header }
                        .accessibilityIdentifier("account-member-profile")
                }
                Section("Profiles") { rows(AccountPage.profiles) }
                Section("Settings") { rows(AccountPage.settings) }
                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("account-appearance")
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows your iPhone’s setting.")
                }
                Section {
                    Link(destination: Self.helpURL) {
                        Label("Get Help", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("account-get-help")
                }
                Section {
                    Button(role: .destructive) {
                        // Close first, so the sheet isn't torn down mid-
                        // presentation when the signed-in tree goes away.
                        presenter.dismiss()
                        Task { await authService.logout() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityIdentifier("account-sign-out")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AxialColor.layer2)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { presenter.dismiss() }
                }
            }
            .navigationDestination(for: AccountPage.self) { page in
                AccountPlaceholderPage(page: page)
            }
        }
        .tint(AxialColor.brandPrimary)
        .accessibilityIdentifier("account-sheet")
    }

    /// The web shows a "passport" card here, with company and rating. Those
    /// need the current account from `/me` (CHALLENGES #14), so for now the
    /// card carries what Auth0 gives us.
    private var header: some View {
        HStack(spacing: 14) {
            UserAvatar(name: authService.user?.name, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(authService.user?.name ?? "Your Account")
                    .font(.headline)
                    .foregroundStyle(AxialColor.textPrimary)
                if let email = authService.user?.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(AxialColor.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func rows(_ pages: [AccountPage]) -> some View {
        ForEach(pages) { page in
            NavigationLink(value: page) {
                Label(page.title, systemImage: page.systemImage)
                    .foregroundStyle(AxialColor.textPrimary)
            }
            .accessibilityIdentifier("account-\(page.rawValue)")
        }
    }
}

/// Stands in for each page until it's built. Most of them need the current
/// account, which arrives with `/me`.
private struct AccountPlaceholderPage: View {
    let page: AccountPage

    var body: some View {
        ContentUnavailableView(
            page.title,
            systemImage: page.systemImage,
            description: Text("Not available on mobile yet.")
        )
        .background(AxialColor.layer2)
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
