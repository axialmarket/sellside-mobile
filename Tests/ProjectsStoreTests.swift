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
}
