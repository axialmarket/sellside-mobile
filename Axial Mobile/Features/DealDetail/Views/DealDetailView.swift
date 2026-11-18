//
//  DealDetailView.swift
//  Axial Mobile
//

import SwiftUI
import UIKit
import QuickLook

/// One deal, opened from a member list. Mobile's take on the web's sell
/// sidebar (`SellSidebarComponent`, sell-sidebar.component.ts), which
/// slides over the grid rather than being a page of its own: a header, three
/// tabs, the footer's calls to action, an ellipsis menu, and Previous /
/// Next Member through the list it came from.
///
/// The row is read from `ProjectDashboardStore`, so the header renders from
/// the card you tapped and every status change shows here and on the card
/// at once. The profile, conversation and comments come from
/// `DealDetailStore` and fill in behind it.
struct DealDetailView: View {
    let projectId: String
    let pager: DealPager
    /// The card this screen zoomed out of, which it collapses back into.
    let sourceDealId: String
    var transitionNamespace: Namespace.ID?

    @State private var dealId: String
    @State private var tab: DealDetailTab

    @Environment(ProjectDashboardStore.self) private var store
    @Environment(DealDetailStore.self) private var detailStore
    @Environment(ProjectsStore.self) private var projectsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var resolution: DealResolution?
    /// End Discussions or a recommendation's Pass, opening from the footer
    /// button that asked (`Confirmation`).
    @State private var confirmation: Confirmation?
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: Sheet?
    @State private var actionError: String?
    @State private var toast: String?
    /// The file QuickLook is showing; it's deleted when the preview closes.
    @State private var previewURL: URL?
    @State private var openingFileId: String?
    @Environment(\.openURL) private var openURL
    /// The opening tab is chosen once. A full-screen cover (the redline
    /// editor) fires `onAppear` again when it closes.
    @State private var hasChosenTab = false
    /// Where the list asked this screen to open: a tab, a composer, or
    /// neither (the usual opening tab).
    private let startingTab: DealDetailTab?
    private let startingCompose: DealCompose?

    enum Sheet: String, Identifiable {
        case reply, comment
        var id: String { rawValue }
    }

    init(projectId: String, dealId: String, pager: DealPager, transitionNamespace: Namespace.ID? = nil,
         startingTab: DealDetailTab? = nil, startingCompose: DealCompose? = nil) {
        self.startingTab = startingCompose?.tab ?? startingTab
        self.startingCompose = startingCompose
        self.projectId = projectId
        self.pager = pager
        sourceDealId = dealId
        self.transitionNamespace = transitionNamespace
        _dealId = State(initialValue: dealId)
        _tab = State(initialValue: .profile)
    }

    private static let topID = "deal-top"

    // MARK: State we read

    private var dashboard: ProjectDashboard? { store.dashboard(for: projectId) }

    private var deal: SellsideDeal? {
        dashboard?.deals.first { $0.id == dealId }
    }

    private var detail: DealDetailStore.Detail { detailStore.detail(for: dealId) }

    private var actions: DealDetailActions {
        deal.map(DealDetailActions.init(deal:)) ?? DealDetailActions(footer: [], menu: [])
    }

    private var tabs: [DealDetailTab] {
        guard let deal else { return [.profile, .files, .comments] }
        return DealDetailTab.allCases.filter { $0 != .messages || DealDetailActions.showsMessages(for: deal) }
    }

    private var isBusy: Bool { store.isUpdating(dealId: dealId) }

    /// Ids still in the list — a pass or a status change can move a deal
    /// out of it, and paging skips those, as `prevRow` / `nextRow` do.
    private var presentIds: Set<String> { Set(dashboard?.deals.map(\.id) ?? []) }

    private var projectName: String {
        dashboard?.project.internalName ?? projectsStore.project(withIntentId: projectId)?.internalName ?? ""
    }

    // MARK: Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DealHeader(deal: deal, profile: detail.profile)
                        .id(Self.topID)
                    tabPicker
                    tabContent
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A new member starts at the top, rather than wherever the last
            // one was scrolled to.
            .onChange(of: dealId) { _, _ in proxy.scrollTo(Self.topID, anchor: .top) }
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(AxialColor.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DealFooter(deal: deal, buttons: actions.footer, tabAction: tabAction, isBusy: isBusy,
                       confirmation: $confirmation,
                       onTap: handle(_:), onUpdateStatus: { mark(as: $0.status) })
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: tabAction)
        }
        .zoomingFrom(sourceDealId, in: transitionNamespace)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(deal?.displayName ?? "")
        .navigationSubtitle(projectName)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                pageButton(previous: true)
                pageButton(previous: false)
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .task(id: dealId) {
            async let dashboard: Void = store.loadIfNeeded(id: projectId)
            async let detail: Void = detailStore.loadIfNeeded(dealId: dealId)
            _ = await (dashboard, detail)
            // Warm the members either side, so Previous / Next usually lands
            // on a profile that's already here instead of filling in after.
            // Not until the push has settled: their requests and decoding
            // run on the main thread, and mid-transition that's a dropped
            // frame. Paging on cancels this and starts again.
            guard (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
            for neighbour in [pager.previous(from: dealId, among: presentIds),
                              pager.next(from: dealId, among: presentIds)].compactMap({ $0 }) {
                Task(priority: .utility) { await detailStore.loadIfNeeded(dealId: neighbour) }
            }
        }
        .onAppear {
            guard !hasChosenTab else { return }
            hasChosenTab = true
            // Every member opens on the profile, unless the list asked for a
            // tab (the actions sheet's View rows).
            tab = startingTab.flatMap { tabs.contains($0) ? $0 : nil } ?? .profile
        }
        .task {
            guard let startingCompose else { return }
            // After the push has landed: a sheet asked for mid-transition
            // is dropped.
            try? await Task.sleep(for: .milliseconds(450))
            sheet = switch startingCompose {
            case .message: .reply
            case .comment: .comment
            }
        }
        // A status change can take the Messages tab away (or bring it back).
        .onChange(of: tabs) { _, tabs in if !tabs.contains(tab) { tab = .profile } }
        .refreshable {
            async let dashboard = store.load(id: projectId)
            async let detail: Void = detailStore.load(dealId: dealId)
            let (succeeded, _) = await (dashboard, detail)
            succeeded ? Haptics.success() : Haptics.error()
        }
        .dealResolver(projectId: projectId, request: $resolution)
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .alert("Couldn't update this member", isPresented: errorBinding, presenting: actionError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { old, new in
            if let old, new == nil { DealFilePreview.discard(old) }
        }
        .onChange(of: dealId) { _, _ in openingFileId = nil }
        .overlay(alignment: .top) { toastView }
        .animation(reduceMotion ? nil : .snappy, value: toast)
    }

    // MARK: Tabs

    /// The open tab's own action, pinned above the footer's calls to action:
    /// Reply on Messages, for a member you can write to; Add Internal Comment
    /// on Comments.
    private var tabAction: DealFooter.TabAction? {
        switch tab {
        case .messages where deal.map(DealDetailActions.canMessage) == true:
            DealFooter.TabAction(title: "Reply", systemImage: "arrowshape.turn.up.left", id: "deal-reply") {
                sheet = .reply
            }
        case .comments:
            DealFooter.TabAction(title: "Add Internal Comment", systemImage: "plus", id: "deal-add-comment") {
                sheet = .comment
            }
        default:
            nil
        }
    }

    /// The web's tab names, "Company Profile" included, each segment sized
    /// to its label (`DealTabBar`).
    private var tabPicker: some View {
        DealTabBar(tabs: tabs, selection: $tab)
    }

    /// Four genuinely different shapes, so this is a real swap — each
    /// cross-fades rather than popping.
    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .profile:
            DealProfileTab(deal: deal, profile: detail.profile, error: detail.profileError,
                           onRetry: reload, onCopyEmail: copy(email:))
                .transition(.opacity)
        case .messages:
            DealMessagesTab(feed: detailStore.feed(for: dealId, row: deal),
                            isLoaded: detail.hasLoadedFeed, error: detail.feedError,
                            hasLegacyMessages: detail.profile?.hasLegacyMessages ?? false,
                            isMine: detailStore.isMine, onRetry: reload)
                .transition(.opacity)
        case .files:
            DealFilesTab(files: detailStore.files(for: dealId), isLoaded: detail.hasLoadedProfile,
                         openingFileId: openingFileId, onOpen: open(_:))
                .transition(.opacity)
        case .comments:
            DealCommentsTab(notes: detail.sources.notes, isLoaded: detail.hasLoadedNotes,
                            error: detail.notesError, isOwn: detailStore.isOwn,
                            onDelete: delete(_:), onRetry: reload)
                .transition(.opacity)
        }
    }

    // MARK: Toolbar

    /// Previous / Next Member — `SellSidebarActionsComponent`. Plain bar
    /// buttons whose disabled state changes; the items themselves never do.
    private func pageButton(previous: Bool) -> some View {
        let target = previous
            ? pager.previous(from: dealId, among: presentIds)
            : pager.next(from: dealId, among: presentIds)
        return Button {
            guard let target else { return }
            Haptics.selection()
            // Instant, as Mail's arrows are. Animating the swap tweened every
            // difference between the two members' layouts.
            dealId = target
        } label: {
            Label(previous ? "Previous Member" : "Next Member",
                  systemImage: previous ? "chevron.up" : "chevron.down")
        }
        .disabled(target == nil || isBusy)
        .accessibilityIdentifier(previous ? "deal-previous" : "deal-next")
    }

    /// The sidebar's ellipsis dropdown. One `Menu` whose label never
    /// changes; its items follow the deal.
    private var moreMenu: some View {
        Menu {
            ForEach(actions.menu, id: \.self) { item in
                menuItem(item)
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .disabled(actions.menu.isEmpty || isBusy)
        .tint(AxialColor.textPrimary)
        .accessibilityIdentifier("deal-more-menu")
    }

    @ViewBuilder
    private func menuItem(_ item: DealDetailActions.MenuItem) -> some View {
        switch item {
        case .sendCim:
            Button("Send CIM", systemImage: "paperplane") { handle(.sendCim) }
        case .sendMessage:
            Button("Send Message", systemImage: "envelope") { sheet = .reply }
        case .reviewRedlines:
            Button("Review Redlines", systemImage: DealResolveAction.reviewRedlines.systemImage) {
                handle(.reviewRedlines)
            }
        case .addComment:
            Button("Add Internal Comment", systemImage: "bubble.left") { sheet = .comment }
        case .updateStatus:
            Menu {
                DealStatusMenuItems { mark(as: $0.status) }
            } label: {
                Label("Update Status", systemImage: "arrow.triangle.2.circlepath")
            }
        case .copyEmail:
            Button("Copy Email", systemImage: "envelope.badge") {
                if let email = detail.profile?.contact?.email { copy(email: email) }
            }
            .disabled(detail.profile?.contact?.email == nil)
        case .copyPhone:
            Button("Copy Phone Number", systemImage: "phone") { copyPhone() }
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        let name = deal?.displayName ?? ""
        switch sheet {
        case .reply:
            ReplySheet(
                draft: MessageDraft.reply(
                    latest: detail.sources.messages.max { $0.sentAt < $1.sentAt },
                    me: detailStore.currentUser, contact: detail.profile?.contact,
                    headline: detail.profile?.headline ?? dashboard?.project.internalName),
                subtitle: name,
                // `!deal.hasTargetPursued` — the web's anonymity note.
                note: (deal?.hasTargetPursued ?? true) ? nil
                    : "Your identity remains hidden until this member pursues the deal."
            ) { draft in
                try await detailStore.send(draft, dealId: dealId)
                tab = .messages
            }
        case .comment:
            DealComposeSheet(title: "Add Internal Comment", subtitle: name, sendLabel: "Add",
                             placeholder: "Write a comment",
                             note: "Comments are only visible to your team.") { text in
                try await detailStore.addNote(text, dealId: dealId)
                tab = .comments
            }
        }
    }

    // MARK: Actions

    private func handle(_ button: DealDetailActions.Button) {
        guard let deal else { return }
        Haptics.lightImpact()
        switch button {
        case .endDiscussions:
            confirmation = Confirmation(
                anchor: DealFooter.anchor(button), title: "End Discussions",
                message: "You're about to end discussions with \(deal.displayName).",
                confirm: "End Discussions") { mark(as: .endedDiscussions) }
        case .restartDiscussions: restartDiscussions()
        case .pass:
            // A recommendation passes through its own endpoint and
            // confirmation; an access request through the resolver's.
            // `openPassOnMemberModal` (sell-actions.service.ts).
            if deal.supplyStatus == .notShared {
                let name = deal.demandAccountName ?? deal.displayName
                confirmation = Confirmation(
                    anchor: DealFooter.anchor(button), title: "Pass on Member",
                    message: "You're about to pass on \(name) and remove them from your list. This cannot be undone.",
                    confirm: "Pass on Member") { passRecommended() }
            } else {
                resolution = .pass([deal])
            }
        case .accept: resolution = .accept([deal])
        case .sendCim: resolution = .shareCim([deal])
        case .reviewRedlines: resolution = .reviewRedlines(deal)
        case .updateStatus: break // a menu; see DealFooter
        }
    }

    /// No confirmation, as on the web.
    private func restartDiscussions() {
        Task {
            do {
                try await store.restartDiscussions([dealId], on: projectId)
                Haptics.success()
                await detailStore.loadFeed(dealId)
            } catch {
                Haptics.error()
                actionError = error.localizedDescription
            }
        }
    }

    /// `deals/sellside/pass`. The member leaves the list, so the screen
    /// goes back to it, as the web's sidebar closes.
    private func passRecommended() {
        Task {
            do {
                try await store.passRecommended([dealId], on: projectId)
                Haptics.success()
                dismiss()
            } catch {
                Haptics.error()
                actionError = error.localizedDescription
            }
        }
    }

    private func mark(as status: DealStatus) {
        Task {
            do {
                try await store.markDeals([dealId], as: status, on: projectId)
                Haptics.success()
                // The history line for the change lands on the next fetch.
                await detailStore.loadFeed(dealId)
            } catch {
                Haptics.error()
                actionError = error.localizedDescription
            }
        }
    }

    private func delete(_ note: DealNote) {
        Task {
            do {
                try await detailStore.deleteNote(note, dealId: dealId)
                Haptics.success()
            } catch {
                Haptics.error()
                actionError = error.localizedDescription
            }
        }
    }

    /// A link opens in the browser; anything else downloads and opens in
    /// QuickLook.
    private func open(_ file: DealFile) {
        if case .link(let url) = file.source {
            openURL(url)
            return
        }
        let dealId = dealId
        openingFileId = file.id
        Task {
            defer { if openingFileId == file.id { openingFileId = nil } }
            do {
                let url = try await detailStore.previewURL(for: file, dealId: dealId)
                guard self.dealId == dealId else { return DealFilePreview.discard(url) }
                previewURL = url
            } catch {
                Haptics.error()
                actionError = "Couldn’t open \(file.filename). \(error.localizedDescription)"
            }
        }
    }

    private func reload() {
        Task { await detailStore.load(dealId: dealId) }
    }

    private func copy(email: String) {
        UIPasteboard.general.string = email
        Haptics.success()
        showToast("Email copied")
    }

    private func copyPhone() {
        Task {
            do {
                UIPasteboard.general.string = try await detailStore.phoneNumber(dealId: dealId)
                Haptics.success()
                showToast("Phone number copied")
            } catch {
                Haptics.error()
                showToast("No phone number on file")
            }
        }
    }

    // MARK: Feedback

    private var toastView: some View {
        Text(toast ?? "")
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: Capsule())
            .padding(.top, 8)
            .opacity(toast == nil ? 0 : 1)
            .offset(y: toast == nil && !reduceMotion ? -12 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(toast == nil)
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == message { toast = nil }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }
}

// MARK: - Footer

/// The sidebar's CTA footer: secondary on the left, primary on the right,
/// each its own lens with 12pt between them. Update Status is a menu that
/// looks like its neighbours.
private struct DealFooter: View {
    /// A tab's own button, on its own row above the calls to action.
    struct TabAction: Equatable {
        let title: String
        let systemImage: String
        let id: String
        let perform: () -> Void

        static func == (lhs: TabAction, rhs: TabAction) -> Bool { lhs.id == rhs.id }
    }

    let deal: SellsideDeal?
    let buttons: [DealDetailActions.Button]
    let tabAction: TabAction?
    let isBusy: Bool
    /// A button's confirmation opens from that button.
    let confirmation: Binding<Confirmation?>
    let onTap: (DealDetailActions.Button) -> Void
    let onUpdateStatus: (DealStatusUpdateOption) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let tabAction {
                Button(action: tabAction.perform) {
                    Label(tabAction.title, systemImage: tabAction.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AxialColor.brandPrimary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier(tabAction.id)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if !buttons.isEmpty {
                ctaRow
                    .disabled(isBusy)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, buttons.isEmpty && tabAction == nil ? 0 : 10)
        .animation(.easeOut(duration: 0.2), value: buttons)
    }

    private var ctaRow: some View {
        HStack(spacing: 12) {
            ForEach(buttons, id: \.self) { button in
                if button == .updateStatus {
                    Menu {
                        DealStatusMenuItems(title: "Update Status", onSelect: onUpdateStatus)
                    } label: {
                        label(for: button)
                    }
                    .modifier(FooterButtonStyle(isPrimary: button.isPrimary))
                    .accessibilityIdentifier("deal-footer-updateStatus")
                } else {
                    Button { onTap(button) } label: { label(for: button) }
                        .modifier(FooterButtonStyle(isPrimary: button.isPrimary))
                        .confirmation(confirmation, anchor: Self.anchor(button))
                        .accessibilityIdentifier("deal-footer-\(button)")
                }
            }
        }
    }

    static func anchor(_ button: DealDetailActions.Button) -> String { "footer-\(button)" }

    private func label(for button: DealDetailActions.Button) -> some View {
        Label(deal.map { button.label(for: $0) } ?? "", systemImage: button.systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
    }
}

private struct FooterButtonStyle: ViewModifier {
    let isPrimary: Bool

    func body(content: Content) -> some View {
        if isPrimary {
            content.buttonStyle(.glassProminent).tint(AxialColor.brandPrimary)
        } else {
            content.buttonStyle(.glass).tint(AxialColor.textPrimary)
        }
    }
}

// MARK: - Reply

/// A reply, with its To and Subject above the body.
private struct ReplySheet: View {
    @State var draft: MessageDraft
    let subtitle: String
    let note: String?
    let onSend: (MessageDraft) async throws -> Void

    var body: some View {
        DealComposeSheet(
            title: "New Message", subtitle: subtitle, sendLabel: "Send", placeholder: "Write a message",
            note: note, canSend: { [to = draft.to] text in
                !to.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            text: draft.body,
            header: { MessageHeaderFields(to: draft.to, subject: $draft.subject) }
        ) { text in
            var outgoing = draft
            outgoing.body = text
            try await onSend(outgoing)
        }
    }
}
