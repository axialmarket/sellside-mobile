//
//  ProjectsStoreTests.swift
//  Tests
//

import Testing
@testable import Axial_Mobile

struct ProjectsStoreTests {

    @Test func groupsInSectionOrderOmittingEmptySections() {
        let projects: [SellsideProject] = [
            .mock(name: "Zeta", state: .draft),
            .mock(name: "Alpha", state: .inMarket),
            .mock(name: "Beta", state: .inMarket),
        ]
        let sections = ProjectsStore.grouped(projects)
        #expect(sections.map(\.state) == [.inMarket, .draft])
        #expect(sections[0].projects.map(\.internalName) == ["Alpha", "Beta"])
        #expect(sections[1].projects.map(\.internalName) == ["Zeta"])
    }

    @Test func sortsWithinSectionCaseInsensitively() {
        let sections = ProjectsStore.grouped([
            .mock(name: "beta", state: .inMarket),
            .mock(name: "Alpha", state: .inMarket),
        ])
        #expect(sections[0].projects.map(\.internalName) == ["Alpha", "beta"])
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
}
