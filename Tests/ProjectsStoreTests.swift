//
//  ProjectsStoreTests.swift
//  Tests
//

import Testing
@testable import Sellside_Mobile

struct ProjectsStoreTests {

    // SELL_INTENT_STATUS_FUNNEL (deal-status.constants.ts).
    @Test func groupsInFunnelOrderOmittingEmptySections() {
        let projects: [SellsideProject] = [
            .mock(name: "Zeta", state: .underLoi),
            .mock(name: "Alpha", state: .draft),
            .mock(name: "Beta", state: .inMarket),
        ]
        let sections = ProjectsStore.grouped(projects)
        #expect(sections.map(\.state) == [.inMarket, .draft, .underLoi])
    }

    // SellsideProjectsStore.projects (sellside-projects.store.ts) sorts by
    // funnel position only, so the server's order survives inside a status.
    @Test func keepsTheServersOrderWithinASection() {
        let sections = ProjectsStore.grouped([
            .mock(name: "Zeta", state: .inMarket),
            .mock(name: "Gamma", state: .draft),
            .mock(name: "Alpha", state: .inMarket),
        ])
        #expect(sections[0].projects.map(\.internalName) == ["Zeta", "Alpha"])
    }

    @Test func unknownStatesGroupLast() {
        let sections = ProjectsStore.grouped([
            .mock(name: "Mystery", state: .unknown),
            .mock(name: "Live", state: .inMarket),
        ])
        #expect(sections.map(\.state) == [.inMarket, .unknown])
    }

    // MARK: - Patching from a whole-project response

    @Test func applyingReplacesNameAndStatusOnTheMatchingRow() {
        let projects: [SellsideProject] = [
            .mock(publicId: "aaa-bbb", name: "Old Name", state: .draft, recommended: 24),
            .mock(publicId: "ccc-ddd", name: "Other", state: .inMarket),
        ]
        let updated = ProjectsStore.applying(
            ProjectDetail(id: "aaabbb", internalName: "New Name", supplyState: .underLoi),
            to: projects
        )
        #expect(updated[0].internalName == "New Name")
        #expect(updated[0].supplyState == .underLoi)
        // Counts only come from the list endpoint, so they survive the patch.
        #expect(updated[0].activeRecommendations == 24)
        #expect(updated[1] == projects[1])
    }

    @Test func applyingAnUnknownProjectLeavesTheListAlone() {
        let projects: [SellsideProject] = [.mock(publicId: "aaa-bbb", name: "Old Name")]
        let updated = ProjectsStore.applying(
            ProjectDetail(id: "999", internalName: "Nope"), to: projects
        )
        #expect(updated == projects)
    }

    @Test func patchedRowRegroupsIntoItsNewSection() {
        let projects: [SellsideProject] = [.mock(publicId: "aaa-bbb", name: "Neptune", state: .draft)]
        let updated = ProjectsStore.applying(
            ProjectDetail(id: "aaabbb", internalName: "Neptune", supplyState: .inMarket),
            to: projects
        )
        #expect(ProjectsStore.grouped(updated).map(\.state) == [.inMarket])
    }

    // MARK: - Search

    private static let searchable: [SellsideProject] = [
        .mock(name: "Project Neptune", sectors: ["Industrials", "Manufacturing"]),
        .mock(name: "Gas Station Portfolio", sectors: ["Energy"]),
    ]

    @Test func aBlankQueryMatchesEverything() {
        for query in ["", "   "] {
            #expect(ProjectsStore.matching(query, in: Self.searchable).count == 2)
        }
    }

    @Test func matchesOnNameIgnoringCaseAndSurroundingSpace() {
        let found = ProjectsStore.matching("  neptune ", in: Self.searchable)
        #expect(found.map(\.internalName) == ["Project Neptune"])
    }

    @Test func matchesOnSectorToo() {
        // Sectors are visible on the card, so they're reasonable to search by.
        let found = ProjectsStore.matching("energy", in: Self.searchable)
        #expect(found.map(\.internalName) == ["Gas Station Portfolio"])
    }

    @Test func matchesPartialWordsAnywhereInTheName() {
        #expect(ProjectsStore.matching("station", in: Self.searchable).count == 1)
    }

    @Test func noMatchReturnsEmptyRatherThanEverything() {
        #expect(ProjectsStore.matching("zzz", in: Self.searchable).isEmpty)
    }

    // MARK: - Member lists from the card

    /// Mobile's own: a project card's swipe opens only the lists with members.
    @Test func onlyListsWithMembersAreOffered() {
        let project = SellsideProject.mock(recommended: 0, contacted: 4, interested: 2)
        #expect(project.listsWithMembers.map(\.bucket) == [.contacted, .interested])
        #expect(project.listsWithMembers.map(\.count) == [4, 2])
        #expect(SellsideProject.mock(recommended: 0, contacted: 0, interested: 0).listsWithMembers.isEmpty)
    }
}
