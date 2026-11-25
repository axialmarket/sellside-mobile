//
//  ProjectFilterTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Sellside_Mobile

/// Web source: fe-app market-deals-grid.component.ts, `MarketDealsGridComponent`
/// column filters — set filters OR within a column, columns AND together.
struct ProjectFilterTests {

    // MARK: - Matching

    @Test func anEmptyFilterMatchesEverything() {
        let projects: [SellsideProject] = [.mock(state: .draft), .mock(state: .dead, sectors: [])]
        #expect(!ProjectFilter().isActive)
        #expect(ProjectFilter().apply(to: projects) == projects)
    }

    @Test func statusesOrTogether() {
        let filter = ProjectFilter(statuses: [.inMarket, .draft])
        #expect(filter.matches(.mock(state: .inMarket)))
        #expect(filter.matches(.mock(state: .draft)))
        #expect(!filter.matches(.mock(state: .closed)))
    }

    @Test func separateFiltersAndTogether() {
        let filter = ProjectFilter(statuses: [.inMarket], activity: [.interested])
        #expect(filter.matches(.mock(state: .inMarket, interested: 2)))
        #expect(!filter.matches(.mock(state: .inMarket, interested: 0)))
        #expect(!filter.matches(.mock(state: .draft, interested: 2)))
    }

    @Test func contactMatchesOnFullNameAndUnassignedIsItsOwnBucket() {
        let jordan = SellsideProject.mock(contact: ("Jordan", "Reyes"))
        let nobody = SellsideProject.mock(contact: nil)
        #expect(ProjectFilter(contacts: ["Jordan Reyes"]).matches(jordan))
        #expect(!ProjectFilter(contacts: ["Jordan Reyes"]).matches(nobody))
        #expect(ProjectFilter(contacts: [ProjectFilter.unassigned]).matches(nobody))
    }

    @Test func sectorMatchesWhenAnyOfTheProjectsSectorsIsSelected() {
        let filter = ProjectFilter(sectors: ["Healthcare"])
        #expect(filter.matches(.mock(sectors: ["Industrials", "Healthcare"])))
        #expect(!filter.matches(.mock(sectors: ["Industrials"])))
        #expect(!filter.matches(.mock(sectors: [])))
    }

    @Test func activityTogglesEachRequireANonZeroCount() {
        #expect(ProjectFilter(activity: [.newRecommendations]).matches(.mock(unread: 1)))
        #expect(!ProjectFilter(activity: [.newRecommendations]).matches(.mock(unread: 0)))
        #expect(!ProjectFilter(activity: [.newRecommendations]).matches(.mock(unread: nil)))
        #expect(ProjectFilter(activity: [.contacted]).matches(.mock(contacted: 1)))
        #expect(!ProjectFilter(activity: [.contacted]).matches(.mock(contacted: 0)))
    }

    // MARK: - Created window

    @Test func createdWindowIncludesProjectsInsideItAndDropsOlderOnes() {
        let filter = ProjectFilter(created: .pastMonth)
        #expect(filter.matches(.mock(createdDaysAgo: 3)))
        #expect(!filter.matches(.mock(createdDaysAgo: 60)))
    }

    @Test func createdWindowDropsProjectsWithNoCreationDate() {
        // The web's agDateColumnFilter excludes blanks the same way.
        #expect(!ProjectFilter(created: .pastYear).matches(.mock(createdDaysAgo: nil)))
    }

    @Test func createdWindowIsMeasuredFromTheInjectedNow() {
        let now = Date.now
        let created = Calendar.current.date(byAdding: .day, value: -10, to: now)!
        let project = SellsideProject(publicId: "a", internalName: "A", supplyState: .inMarket,
                                      createdAt: created)
        let filter = ProjectFilter(created: .pastWeek)
        #expect(!filter.matches(project, now: now))
        let earlier = Calendar.current.date(byAdding: .day, value: -5, to: now)!
        #expect(filter.matches(project, now: earlier))
    }

    // MARK: - Badge count

    @Test func activeCountIsOnePerCategoryNotPerValue() {
        let filter = ProjectFilter(statuses: [.inMarket, .draft, .closed], created: .pastWeek)
        #expect(filter.activeCount == 2)
    }

    // MARK: - Options

    @Test func statusOptionsFollowSectionOrderAndOnlyListStatusesPresent() {
        let options = ProjectFilterOptions(projects: [
            .mock(state: .draft), .mock(state: .inMarket), .mock(state: .inMarket),
        ])
        #expect(options.statuses.map(\.value) == [.inMarket, .draft])
        #expect(options.statuses.map(\.count) == [2, 1])
    }

    @Test func contactOptionsSortAlphabeticallyWithUnassignedLast() {
        let options = ProjectFilterOptions(projects: [
            .mock(contact: nil),
            .mock(contact: ("Sam", "Okafor")),
            .mock(contact: ("alex", "Chen")),
        ])
        #expect(options.contacts.map(\.label) == ["alex Chen", "Sam Okafor", "Unassigned"])
    }

    @Test func sectorOptionsCountEachProjectOnce() {
        let options = ProjectFilterOptions(projects: [
            .mock(sectors: ["Healthcare", "Healthcare"]),
            .mock(sectors: ["Healthcare", "Industrials"]),
        ])
        #expect(options.sectors.map(\.value) == ["Healthcare", "Industrials"])
        #expect(options.sectors.map(\.count) == [2, 1])
    }

    @Test func aSelectionNoLongerInTheListStaysVisibleAtZero() {
        // Otherwise a refresh could leave a filter on that the user can't see to remove.
        let options = ProjectFilterOptions(
            projects: [.mock(state: .inMarket, sectors: ["Industrials"])],
            selected: ProjectFilter(statuses: [.closed], sectors: ["Healthcare"])
        )
        #expect(options.statuses.map(\.value) == [.inMarket, .closed])
        #expect(options.sectors.first { $0.value == "Healthcare" }?.count == 0)
    }

    @Test func summaryNamesASingleChoiceAndCountsSeveral() {
        let options = ProjectFilterOptions(projects: [
            .mock(contact: ("Sam", "Okafor")), .mock(contact: nil),
        ]).contacts
        #expect(ProjectFilterOptions.summary(of: [], in: options) == "Any")
        #expect(ProjectFilterOptions.summary(of: [ProjectFilter.unassigned], in: options) == "Unassigned")
        #expect(ProjectFilterOptions.summary(of: ["Sam Okafor", ""], in: options) == "2 selected")
    }

    // MARK: - Store

    @Test func sectionsApplySearchAndFilterTogether() {
        let projects: [SellsideProject] = [
            .mock(name: "Neptune Alpha", state: .inMarket),
            .mock(name: "Neptune Beta", state: .draft),
            .mock(name: "Orion", state: .inMarket),
        ]
        let narrowed = ProjectFilter(statuses: [.inMarket])
            .apply(to: ProjectsStore.matching("neptune", in: projects))
        #expect(ProjectsStore.grouped(narrowed).flatMap(\.projects).map(\.internalName) == ["Neptune Alpha"])
    }
}
