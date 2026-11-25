//
//  ProjectDashboardStoreTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Sellside_Mobile

@MainActor
struct ProjectDashboardStoreTests {

    private static let id = "aaabbb"
    private static let intentPath = "intents/aaabbb"
    private static let dealsPath = "intents/sellside/aaabbb/deals"

    private static let intentJSON = """
    {"id": "aaa-bbb", "internal_name": "Project Neptune", "supply_state": "in_market"}
    """
    private static let dealsJSON = """
    [{"public_id": "d1", "demand_account_public_id": "a1",
      "demand_account_name": "Bluewater Capital", "is_interested": true,
      "supply_status": "sent_teaser"},
     {"public_id": "d2", "demand_account_public_id": "a2",
      "demand_account_name": "Harbor Point", "supply_status": "target_signed_nda"}]
    """

    private func makeStore(
        _ responses: [String: StubAPI.Response]
    ) -> (ProjectDashboardStore, ProjectsStore, StubAPI) {
        let api = StubAPI(responses: responses)
        let projectsStore = ProjectsStore(apiClient: api)
        return (ProjectDashboardStore(apiClient: api, projectsStore: projectsStore), projectsStore, api)
    }

    private var loadingResponses: [String: StubAPI.Response] {
        [Self.intentPath: .json(Self.intentJSON), Self.dealsPath: .json(Self.dealsJSON)]
    }

    // MARK: - Combined load

    @Test func loadsTheProjectAndItsDealsTogether() async {
        let (store, _, api) = makeStore(loadingResponses)
        await store.load(id: Self.id)

        guard case .loaded(let dashboard) = store.state(for: Self.id) else {
            Issue.record("expected .loaded, got \(store.state(for: Self.id))")
            return
        }
        #expect(dashboard.project.internalName == "Project Neptune")
        #expect(dashboard.deals.count == 2)
        #expect(dashboard.counterpartyOptions.map(\.name) == ["Bluewater Capital", "Harbor Point"])
        #expect(Set(api.requestedPaths) == [Self.intentPath, Self.dealsPath])
    }

    @Test func eitherRequestFailingFailsTheWholeLoad() async {
        // The dashboard's actions need the deals, so half of it is no use.
        for failing in [Self.intentPath, Self.dealsPath] {
            var responses = loadingResponses
            responses[failing] = .failure(APIError.server(500, path: failing, body: "boom"))
            let (store, _, _) = makeStore(responses)

            await store.load(id: Self.id)

            #expect(store.dashboard(for: Self.id) == nil, "\(failing) failure still produced a dashboard")
            guard case .failed = store.state(for: Self.id) else {
                Issue.record("expected .failed for \(failing)")
                return
            }
        }
    }

    /// Elementals are VPN-only; the gateway answers 503 off it (CHALLENGES #8).
    /// Whether that reads as "connect to the VPN" follows the build's
    /// `API_REQUIRES_VPN`.
    @Test func aGatewayTurnAwayIsSurfacedAsOffNetworkOnlyBehindTheVPN() async {
        var responses = loadingResponses
        responses[Self.intentPath] = .failure(APIError.server(503, path: Self.intentPath, body: nil))
        let (store, _, _) = makeStore(responses)

        await store.load(id: Self.id)

        #expect((store.state(for: Self.id) == .offNetwork) == APIEnvironment.requiresVPN)
    }

    @Test func gatewayRejectionsAreTheGatewaysAnswersOnly() {
        #expect(APIError.server(503, path: "p", body: nil).isGatewayRejection)
        #expect(APIError.server(403, path: "p", body: "RBAC: access denied").isGatewayRejection)
        #expect(!APIError.server(403, path: "p", body: "{\"detail\": \"Forbidden\"}").isGatewayRejection)
        #expect(!APIError.server(500, path: "p", body: nil).isGatewayRejection)
    }

    @Test func onlyAVPNOnlyAPIAsksForTheVPN() {
        let unavailable = APIError.server(503, path: "p", body: nil)
        #expect(unavailable.isOffNetwork(requiresVPN: true))
        #expect(!unavailable.isOffNetwork(requiresVPN: false))
    }

    @Test func aUnauthorizedResponseIsSurfacedSeparatelySoTheSessionCanEnd() async {
        var responses = loadingResponses
        responses[Self.intentPath] = .failure(APIError.unauthorized)
        let (store, _, _) = makeStore(responses)

        await store.load(id: Self.id)

        #expect(store.state(for: Self.id) == .unauthorized)
    }

    @Test func loadIfNeededSkipsTheFetchWhenAlreadyCached() async {
        let (store, _, api) = makeStore(loadingResponses)
        await store.load(id: Self.id)
        let afterFirst = api.requestedPaths.count

        await store.loadIfNeeded(id: Self.id)

        #expect(api.requestedPaths.count == afterFirst)
    }

    @Test func concurrentLoadsCollapseIntoOneFetch() async {
        let (store, _, api) = makeStore(loadingResponses)
        // Hold the first fetch open so the second arrives while it's in flight.
        let gate = AsyncGate()
        api.gate = { await gate.wait() }

        async let first = store.load(id: Self.id)
        await Task.yield()
        async let second = store.load(id: Self.id)
        await Task.yield()
        gate.open()

        _ = await (first, second)
        #expect(api.requestedPaths.count == 2, "expected one intent + one deals request")
    }

    // MARK: - Actions

    @Test func performingAnActionPatchesLocalStateFromItsOwnResponse() async throws {
        var responses = loadingResponses
        responses["intents/aaabbb/sellside-put-on-hold"] = .json("""
        {"id": "aaa-bbb", "internal_name": "Project Neptune", "supply_state": "on_hold"}
        """)
        let (store, _, api) = makeStore(responses)
        await store.load(id: Self.id)
        let requestsAfterLoad = api.requestedPaths.count

        try await store.perform(.onHold, on: Self.id)

        #expect(store.dashboard(for: Self.id)?.project.supplyState == .onHold)
        // One POST, and no re-GET: the response carried the whole project.
        #expect(api.requestedPaths.count == requestsAfterLoad + 1)
    }

    @Test func aStatusChangeKeepsTheDealsWeAlreadyHold() async throws {
        var responses = loadingResponses
        responses["intents/aaabbb/sellside-reviewing-lois"] = .json("""
        {"id": "aaa-bbb", "internal_name": "Project Neptune", "supply_state": "reviewing_lois"}
        """)
        let (store, _, _) = makeStore(responses)
        await store.load(id: Self.id)

        try await store.perform(.reviewingLois, on: Self.id)

        // The status endpoints return the intent alone; nothing about who's
        // been contacted changed.
        #expect(store.dashboard(for: Self.id)?.deals.count == 2)
    }

    @Test func counterpartyActionsPostTheBody() async throws {
        let path = "intents/aaabbb/sellside-closed"
        var responses = loadingResponses
        responses[path] = .json("""
        {"id": "aaa-bbb", "internal_name": "Project Neptune", "supply_state": "closed"}
        """)
        let (store, _, api) = makeStore(responses)
        await store.load(id: Self.id)

        try await store.perform(
            .closed,
            on: Self.id,
            counterparty: .make(selection: .member("a1"), customName: "", sourcedViaAxial: true)
        )

        let body = try #require(api.postedBodies[path])
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["account_public_id"] as? String == "a1")
        #expect(json?["is_sourced_via_axial"] as? Bool == true)
    }

    @Test func aFailedActionLeavesLocalStateAlone() async {
        var responses = loadingResponses
        responses["intents/aaabbb/sellside-dead"] = .failure(
            APIError.server(500, path: "intents/aaabbb/sellside-dead", body: "boom")
        )
        let (store, _, _) = makeStore(responses)
        await store.load(id: Self.id)

        await #expect(throws: (any Error).self) {
            try await store.perform(.dead, on: Self.id)
        }
        #expect(store.dashboard(for: Self.id)?.project.supplyState == .inMarket)
    }

    // MARK: - Deal status

    private static let markPath = "deals/supply-marking-status"

    @Test func markingADealPatchesItFromTheResponse() async throws {
        var responses = loadingResponses
        responses[Self.markPath] = .json("""
        [{"id": "d1", "supply_status": "marked_nda_signed"}]
        """)
        let (store, _, api) = makeStore(responses)
        store.refreshesAfterResolving = false
        await store.load(id: Self.id)
        let requestsAfterLoad = api.requestedPaths.count

        try await store.markDeals(["d1"], as: .markedNdaSigned, on: Self.id)

        let deals = try #require(store.dashboard(for: Self.id)?.deals)
        #expect(deals[0].supplyStatus == .markedNdaSigned)
        #expect(deals[0].displayStatus == .targetSignedNda)
        // The untouched deal stays as it was, and the patch didn't wait on a
        // refetch (the background refresh is off here).
        #expect(deals[1].supplyStatus == .targetSignedNda)
        #expect(api.requestedPaths.count == requestsAfterLoad + 1)
    }

    // SellsideDealApiService.endDiscussions.
    @Test func endingDiscussionsUsesTheDedicatedEndpoint() async throws {
        var responses = loadingResponses
        responses["deals/sellside/end-discussions"] = .json(#"[{"id": "d1", "supply_status": "ended_discussions"}]"#)
        let (store, _, api) = makeStore(responses)
        store.refreshesAfterResolving = false
        await store.load(id: Self.id)

        try await store.markDeals(["d1"], as: .endedDiscussions, on: Self.id)

        let body = try #require(api.postedBodies["deals/sellside/end-discussions"])
        #expect(try JSONDecoder().decode(JSONValue.self, from: body) == ["public_ids": ["d1"]])
        #expect(api.postedBodies[Self.markPath] == nil)
        #expect(store.dashboard(for: Self.id)?.deals[0].supplyStatus == .endedDiscussions)
    }

    /// No dedicated endpoint (the stub answers 404), so ending falls back to
    /// marking the status, with the body the web's older route posts.
    @Test func endingFallsBackToMarkingTheStatusAndIdsTheWebPosts() async throws {
        var responses = loadingResponses
        responses[Self.markPath] = .json("[]")
        let (store, _, api) = makeStore(responses)
        await store.load(id: Self.id)

        try await store.markDeals(["d1", "d2"], as: .endedDiscussions, on: Self.id)

        let body = try #require(api.postedBodies[Self.markPath])
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["status"] as? String == "ended_discussions")
        #expect(json?["public_ids"] as? [String] == ["d1", "d2"])
    }

    @Test func aFailedMarkLeavesTheDealAloneAndClearsTheBusyFlag() async {
        var responses = loadingResponses
        responses[Self.markPath] = .failure(APIError.server(500, path: Self.markPath, body: "boom"))
        let (store, _, _) = makeStore(responses)
        await store.load(id: Self.id)

        await #expect(throws: (any Error).self) {
            try await store.markDeals(["d1"], as: .markedClosed, on: Self.id)
        }
        #expect(store.dashboard(for: Self.id)?.deals[0].supplyStatus == .sentTeaser)
        #expect(!store.isUpdating(dealId: "d1"))
    }

    @Test func markingNothingIsANoOp() async throws {
        let (store, _, api) = makeStore(loadingResponses)
        await store.load(id: Self.id)
        let before = api.requestedPaths.count

        try await store.markDeals([], as: .markedClosed, on: Self.id)

        #expect(api.requestedPaths.count == before)
    }

    // MARK: - Cross-store patching

    @Test func loadingAndActingBothPatchTheProjectsList() async throws {
        var responses = loadingResponses
        responses["sellside-projects"] = .json("""
        [{"public_id": "aaa-bbb", "internal_name": "Stale Name", "supply_state": "draft"}]
        """)
        responses["intents/aaabbb/sellside-dead"] = .json("""
        {"id": "aaa-bbb", "internal_name": "Project Neptune", "supply_state": "dead"}
        """)
        let (store, projectsStore, _) = makeStore(responses)
        await projectsStore.load()

        await store.load(id: Self.id)
        #expect(projectsStore.project(withIntentId: Self.id)?.internalName == "Project Neptune")
        #expect(projectsStore.project(withIntentId: Self.id)?.supplyState == .inMarket)

        try await store.perform(.dead, on: Self.id)
        #expect(projectsStore.project(withIntentId: Self.id)?.supplyState == .dead)
    }
}

/// Minimal one-shot gate for holding a stubbed request open.
final class AsyncGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private let lock = NSLock()

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                continuations.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let pending = continuations
        continuations = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}
