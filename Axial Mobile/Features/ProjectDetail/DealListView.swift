//
//  DealListView.swift
//  Axial Mobile
//

import SwiftUI

/// What a member list shows: one whole section, or a dashboard drill-down.
enum DealListSource: Hashable {
    case bucket(SellsideDeal.Bucket)
    case segment(DealSegment)

    var title: String {
        switch self {
        case .bucket(let bucket): bucket.title
        case .segment(let segment): segment.title
        }
    }

    var emptyMessage: String {
        switch self {
        case .bucket(let bucket): bucket.emptyMessage
        case .segment(let segment): segment.emptyMessage
        }
    }

    func deals(in dashboard: ProjectDashboard) -> [SellsideDeal] {
        switch self {
        case .bucket(let bucket): dashboard.deals(in: bucket)
        case .segment(let segment): segment.deals(in: dashboard)
        }
    }
}

/// One section of a project's members, as its own screen.
///
/// Pushed rather than switched, so the section gets a full-width title, its
/// own scroll position and room for its own toolbar later. It also owns the
/// deal actions, because this is the only place deals are listed.
struct DealListView: View {
    let projectId: String
    let source: DealListSource

    @Environment(ProjectDashboardStore.self) private var store
    @Environment(ProjectsStore.self) private var projectsStore

    @State private var endingDiscussionsWith: SellsideDeal?
    /// A card's call to action, carried out by `dealResolver`.
    @State private var resolution: DealResolution?
    /// A card's CIM note or redline editor grows out of its button.
    @Namespace private var resolveTransition
    @State private var actionError: String?
    @State private var searchText = ""
    @State private var filter: DealFilter
    @State private var isFilterPresented = false
    /// The filter sheet zooms out of its bar button.
    @Namespace private var filterTransition
    /// The deal that's been tapped, and the list it was tapped in.
    @State private var openedDeal: OpenedDeal?
    /// A deal's screen grows out of its card.
    @Namespace private var dealTransition
    /// Select mode: the cards toggle instead of opening, and the bottom bar
    /// carries the bulk actions.
    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    /// A bulk change waiting on its confirmation.
    @State private var bulkConfirmation: BulkConfirmation?
    /// A swipe's More, or its Update Status, as a sheet.
    @State private var actionsSheet: ActionsSheetRequest?
    /// What was picked in that sheet, run once it has closed.
    @State private var pendingAction: PendingAction?

    struct ActionsSheetRequest: Identifiable {
        let deal: SellsideDeal
        let startsOnStatus: Bool
        var id: String { deal.id }
    }

    struct PendingAction {
        let deal: SellsideDeal
        let request: DealActionRequest
    }

    /// What a bulk confirmation will do once it's accepted.
    enum BulkConfirmation: Identifiable {
        case status(DealStatusUpdateOption, BulkStatusCopy)
        case endDiscussions(BulkStatusCopy)
        case passRecommended([SellsideDeal])

        var id: String {
            switch self {
            case .status(let option, _): "status-\(option.rawValue)"
            case .endDiscussions: "end"
            case .passRecommended: "pass"
            }
        }

        var title: String {
            switch self {
            case .status(_, let copy), .endDiscussions(let copy): copy.title
            case .passRecommended: "Pass on Member"
            }
        }

        var message: String {
            switch self {
            case .status(_, let copy), .endDiscussions(let copy): copy.message
            case .passRecommended(let deals): RecommendedPassCopy(count: deals.count).message
            }
        }

        var confirm: String {
            switch self {
            case .status(_, let copy), .endDiscussions(let copy): copy.confirm
            case .passRecommended(let deals): RecommendedPassCopy(count: deals.count).confirm
            }
        }

        var isDestructive: Bool {
            if case .status = self { return false }
            return true
        }
    }

    /// `filter` is where the list starts — a member breakdown bar opens it
    /// already narrowed to that bar's members. The seller can change or
    /// clear it from there like any other filter.
    init(projectId: String, source: DealListSource, filter: DealFilter = DealFilter()) {
        self.projectId = projectId
        self.source = source
        _filter = State(initialValue: filter)
    }

    /// Pushed by item rather than through `ProjectsRoute`: the screen pages
    /// through *this* list as it was shown — searched and filtered — which
    /// only this screen knows.
    struct OpenedDeal: Hashable {
        let dealId: String
        let pager: DealPager
        /// From the actions sheet: open on this tab, or with a composer up.
        var tab: DealDetailTab?
        var compose: DealCompose?
    }

    private var dashboard: ProjectDashboard? {
        store.dashboard(for: projectId)
    }

    /// Which project these members belong to. Two screens deep, the title
    /// says "Contacted" and nothing else would say contacted *to what* —
    /// so it rides along as the navigation subtitle.
    ///
    /// Fetched project first, then the list row we already hold, so it's
    /// there before this screen's own load resolves.
    private var projectName: String? {
        dashboard?.project.internalName
            ?? projectsStore.project(withIntentId: projectId)?.internalName
    }

    /// Everyone in this list, before search and filters.
    private var allDeals: [SellsideDeal] {
        dashboard.map(source.deals) ?? []
    }

    /// What the cards show: searched, filtered, most recently updated first.
    private var shownDeals: [SellsideDeal] {
        filter.apply(to: allDeals, query: searchText)
    }

    /// The selection, as far as it's still on screen — a search, a filter or
    /// a member moving lists quietly drops someone from it.
    private var selectedDeals: [SellsideDeal] {
        shownDeals.filter { selectedIds.contains($0.id) }
    }

    private var bulkActions: [DealBulkAction] {
        DealBulkAction.offered(for: selectedDeals)
    }

    var body: some View {
        // A List, not a stack, so the cards can take swipe actions; each row
        // is styled as bare card on the canvas (`dealListRow`).
        List {
            content
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(AxialColor.canvas)
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.large)
        .navigationSubtitle(projectName ?? "")
        .searchable(text: $searchText, prompt: "Search members")
        .navigationBarBackButtonHidden(isSelecting)
        .toolbar { selectionToolbar }
        .toolbar { bottomBar }
        .confirmationDialog(
            bulkConfirmation?.title ?? "",
            isPresented: bulkConfirmationBinding,
            titleVisibility: .visible,
            presenting: bulkConfirmation
        ) { confirmation in
            Button(confirmation.confirm, role: confirmation.isDestructive ? .destructive : nil) {
                run(confirmation)
            }
            Button("Cancel", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message)
        }
        // A swipe's More (and its Update Status) open the actions sheet —
        // Mail's More. Whatever was picked runs once it's gone.
        .sheet(item: $actionsSheet, onDismiss: runPendingAction) { request in
            DealActionsSheet(deal: liveDeal(request.deal), startsOnStatus: request.startsOnStatus) { action in
                pendingAction = PendingAction(deal: request.deal, request: action)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isFilterPresented) {
            DealFilterSheet(filter: $filter, deals: allDeals, matchingCount: shownDeals.count)
                .navigationTransition(.zoom(sourceID: "filter", in: filterTransition))
        }
        .refreshable {
            if await store.load(id: projectId) {
                Haptics.success()
            } else {
                Haptics.error()
            }
        }
        // Normally warm — you arrive here from the project screen — but a
        // cold cache (restored state, a future deep link) still resolves.
        .task { await store.loadIfNeeded(id: projectId) }
        .confirmationDialog(
            "End Discussions",
            isPresented: endDiscussionsBinding,
            titleVisibility: .visible,
            presenting: endingDiscussionsWith
        ) { deal in
            Button("End Discussions", role: .destructive) {
                mark(deal, as: .endedDiscussions)
            }
            Button("Cancel", role: .cancel) {}
        } message: { deal in
            Text("You're about to end discussions with \(deal.displayName).")
        }
        .navigationDestination(item: $openedDeal) { opened in
            DealDetailView(projectId: projectId, dealId: opened.dealId, pager: opened.pager,
                           transitionNamespace: dealTransition,
                           startingTab: opened.tab, startingCompose: opened.compose)
        }
        .dealResolver(projectId: projectId, request: $resolution,
                      zoom: (resolveTransition, { $0.cardSourceID }))
        .alert(
            "Couldn't update this member",
            isPresented: errorBinding,
            presenting: actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Select mode

    /// Select sits top trailing and becomes Select All, then Deselect All
    /// once anything is picked — one button whose label changes, so the bar
    /// morphs it rather than swapping items. Done takes the back button's
    /// place while selecting, as Mail does.
    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { endSelecting() }
                    .accessibilityIdentifier("deals-select-done")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(selectButtonTitle) {
                Haptics.selection()
                if !isSelecting {
                    isSelecting = true
                } else if selectedDeals.isEmpty {
                    selectedIds = Set(shownDeals.map(\.id))
                } else {
                    selectedIds = []
                }
            }
            .disabled(shownDeals.isEmpty)
            .accessibilityIdentifier("deals-select")
        }
    }

    private var selectButtonTitle: String {
        guard isSelecting else { return "Select" }
        return selectedDeals.isEmpty ? "Select All" : "Deselect All"
    }

    /// Browsing: filter, then the system search field, each in its own glass
    /// capsule, as on the projects list. Selecting: the count leading, as the
    /// web's bulk bar leads with it, and the actions trailing.
    @ToolbarContentBuilder
    private var bottomBar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .bottomBar) {
                Text(selectedDeals.isEmpty ? "Select Members" : "\(selectedDeals.count) Selected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AxialColor.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("deals-selected-count")
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItemGroup(placement: .bottomBar) {
                ForEach(bulkActions) { action in
                    bulkButton(action)
                }
            }
        } else {
            ToolbarItem(placement: .bottomBar) {
                FilterToolbarButton(activeCount: filter.activeCount, identifier: "deals-filter-button") {
                    isFilterPresented = true
                }
                .disabled(allDeals.isEmpty)
            }
            .matchedTransitionSource(id: "filter", in: filterTransition)
            ToolbarSpacer(.fixed, placement: .bottomBar)
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }
    }

    @ViewBuilder
    private func bulkButton(_ action: DealBulkAction) -> some View {
        let label = Label(action.label(for: selectedDeals), systemImage: action.systemImage)
        if action == .updateStatus {
            Menu {
                DealStatusMenuItems(groups: DealBulkAction.statusGroups, title: "Update Status",
                                    onSelect: confirmStatus)
            } label: { label }
            .accessibilityIdentifier("deals-bulk-updateStatus")
        } else {
            Button { start(action) } label: { label }
                .accessibilityIdentifier("deals-bulk-\(action)")
        }
    }

    private func toggle(_ deal: SellsideDeal) {
        if selectedIds.contains(deal.id) {
            selectedIds.remove(deal.id)
        } else {
            selectedIds.insert(deal.id)
        }
    }

    private func endSelecting() {
        isSelecting = false
        selectedIds = []
    }

    /// The member type the web's copy names — "3 contacted members".
    private var memberType: String {
        (selectedDeals.first?.bucket.title ?? source.title).lowercased()
    }

    private func start(_ action: DealBulkAction) {
        Haptics.lightImpact()
        let deals = selectedDeals
        switch action {
        case .accept:
            handOff(.accept(deals))
        case .pass:
            if deals.allSatisfy({ $0.bucket == .recommended }) {
                bulkConfirmation = .passRecommended(deals)
            } else {
                handOff(.pass(deals))
            }
        case .shareCim:
            handOff(.shareCim(deals))
        case .endDiscussions:
            bulkConfirmation = .endDiscussions(BulkStatusCopy(endingDiscussionsWith: deals, memberType: memberType))
        case .restartDiscussions:
            // No confirmation, as on the web; ended members only.
            let ended = deals.filter { $0.supplyStatus == .endedDiscussions }.map(\.id)
            runBulk { try await store.restartDiscussions(ended, on: projectId) }
        case .updateStatus:
            break // a menu; see `confirmStatus`
        }
    }

    private func confirmStatus(_ option: DealStatusUpdateOption) {
        bulkConfirmation = .status(option, BulkStatusCopy(updating: selectedDeals, to: option, memberType: memberType))
    }

    /// Accept, pass and Send CIM already have their confirmations and sheets
    /// in `dealResolver`; select mode ends as the request goes over.
    private func handOff(_ resolution: DealResolution) {
        self.resolution = resolution
        endSelecting()
    }

    private func run(_ confirmation: BulkConfirmation) {
        switch confirmation {
        case .status(let option, let copy):
            runBulk { try await store.markDeals(copy.deals.map(\.id), as: option.status, on: projectId) }
        case .endDiscussions(let copy):
            runBulk { try await store.markDeals(copy.deals.map(\.id), as: .endedDiscussions, on: projectId) }
        case .passRecommended(let deals):
            runBulk { try await store.passRecommended(deals.map(\.id), on: projectId) }
        }
    }

    /// Runs a bulk change and leaves select mode once it lands, as the web
    /// clears its grid selection.
    private func runBulk(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                Haptics.success()
                endSelecting()
            } catch {
                Haptics.error()
                actionError = error.localizedDescription
            }
        }
    }

    private var bulkConfirmationBinding: Binding<Bool> {
        Binding(get: { bulkConfirmation != nil }, set: { if !$0 { bulkConfirmation = nil } })
    }

    // MARK: - Content

    /// The count rides above the cards in every loaded state — the pipeline
    /// card showed it on the way in, so it shouldn't vanish on arrival.
    @ViewBuilder
    private var content: some View {
        if dashboard != nil {
            Text(DealFilter.countSummary(shown: shownDeals.count, total: allDeals.count))
                .font(.subheadline)
                .foregroundStyle(AxialColor.textSecondary)
                .contentTransition(.numericText())
                .accessibilityIdentifier("deals-count")
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 3, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        cards
    }

    @ViewBuilder
    private var cards: some View {
        if dashboard == nil {
            DealListSkeleton()
                .dealListRow()
        } else if !allDeals.isEmpty, shownDeals.isEmpty {
            // Members exist; the search or filters hid them all.
            noMatches
                .dealListRow()
        } else {
            DealList(
                deals: shownDeals,
                busyDealIds: store.updatingDealIds,
                emptyMessage: source.emptyMessage,
                transitionNamespace: resolveTransition,
                openNamespace: dealTransition,
                onOpen: { deal in
                    openedDeal = OpenedDeal(dealId: deal.id, pager: DealPager(ids: shownDeals.map(\.id)))
                },
                selectedIds: isSelecting ? selectedIds : nil,
                onToggle: toggle,
                onPickStatus: { actionsSheet = ActionsSheetRequest(deal: $0, startsOnStatus: true) },
                onMore: { actionsSheet = ActionsSheetRequest(deal: $0, startsOnStatus: false) },
                onAction: handle
            )
        }
    }

    private var noMatches: some View {
        VStack(spacing: 12) {
            EmptyStateCard(message: filter.isActive
                           ? "No members match these filters."
                           : "No members match \u{201C}\(searchText)\u{201D}.")
            if filter.isActive {
                Button("Clear Filters") {
                    Haptics.selection()
                    filter = DealFilter()
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("deals-clear-filters")
            }
        }
    }

    private func handle(_ deal: SellsideDeal, _ request: DealActionRequest) {
        switch request {
        case .updateStatus(let option):
            // Web updates a single row straight from its menu; only the bulk
            // path confirms first.
            mark(deal, as: option.status)
        case .endDiscussions:
            endingDiscussionsWith = deal
        case .open(let tab):
            openedDeal = OpenedDeal(dealId: deal.id, pager: DealPager(ids: shownDeals.map(\.id)), tab: tab)
        case .compose(let compose):
            openedDeal = OpenedDeal(dealId: deal.id, pager: DealPager(ids: shownDeals.map(\.id)), compose: compose)
        case .restartDiscussions:
            // No confirmation, as on the web.
            runBulk { try await store.restartDiscussions([deal.id], on: projectId) }
        case .resolve(let action):
            switch action {
            case .accept: resolution = .accept([deal])
            case .pass:
                // A recommendation passes through its own endpoint and
                // confirmation; an access request through the resolver's.
                if deal.bucket == .recommended {
                    bulkConfirmation = .passRecommended([deal])
                } else {
                    resolution = .pass([deal])
                }
            case .reviewRedlines: resolution = .reviewRedlines(deal)
            case .shareCim: resolution = .shareCim([deal])
            }
        }
    }

    private func mark(_ deal: SellsideDeal, as status: DealStatus) {
        Task {
            do {
                try await store.markDeals([deal.id], as: status, on: projectId)
                Haptics.success()
            } catch {
                Haptics.error()
                actionError = error.localizedDescription
            }
        }
    }

    /// The member as the store holds them now, so the sheet follows a
    /// change that lands while it's open.
    private func liveDeal(_ deal: SellsideDeal) -> SellsideDeal {
        allDeals.first { $0.id == deal.id } ?? deal
    }

    private func runPendingAction() {
        guard let pending = pendingAction else { return }
        pendingAction = nil
        handle(liveDeal(pending.deal), pending.request)
    }

    private var endDiscussionsBinding: Binding<Bool> {
        Binding(
            get: { endingDiscussionsWith != nil },
            set: { if !$0 { endingDiscussionsWith = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }
}
