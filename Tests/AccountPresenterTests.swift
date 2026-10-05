//
//  AccountPresenterTests.swift
//  Tests
//

import Testing
@testable import Axial_Mobile

/// Web source: fe-app navbar.component.html, the "Profiles" and "Settings"
/// dropdowns.
struct AccountPresenterTests {

    @Test func presentingWithNoPageOpensAtTheTop() {
        let presenter = AccountPresenter()
        presenter.present()
        #expect(presenter.isPresented)
        #expect(presenter.path.isEmpty)
    }

    @Test func presentingAPageSeedsThePathSoBackLeadsToTheTop() {
        let presenter = AccountPresenter()
        presenter.present(.companySettings)
        #expect(presenter.path == [.companySettings])
    }

    @Test func reopeningAtTheTopClearsAPageLeftFromLastTime() {
        let presenter = AccountPresenter()
        presenter.present(.notifications)
        presenter.dismiss()
        presenter.present()
        #expect(presenter.path.isEmpty)
    }

    @Test func everyPageIsReachableFromTheSheetExactlyOnce() {
        // Member Profile is reached through the header card, as the web's passport.
        let listed = [AccountPage.memberProfile] + AccountPage.profiles + AccountPage.settings
        #expect(listed.count == Set(listed).count)
        #expect(Set(listed) == Set(AccountPage.allCases))
    }

    @Test func initialsTakeUpToTwoWordsUppercased() {
        #expect(AccountInitials.from(name: "jordan reyes") == "JR")
        #expect(AccountInitials.from(name: "Mary Ann de Silva") == "MA")
        #expect(AccountInitials.from(name: "Cher") == "C")
    }

    @Test func initialsFallBackToAWithNoName() {
        #expect(AccountInitials.from(name: nil) == "A")
        #expect(AccountInitials.from(name: "  ") == "A")
    }
}
