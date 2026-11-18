//
//  DealResolver.swift
//  Axial Mobile
//

import SwiftUI

extension View {
    /// Carries out a `DealResolution` raised anywhere on this screen — a
    /// card's button or the dashboard's bulk action — with the web's
    /// confirmations, sheets and messages. One place, so a card and the
    /// dashboard can't word an accept differently.
    ///
    /// `zoom` names where each resolution's sheet grows from — a card's
    /// button on a list, the bulk button on the dashboard.
    func dealResolver(
        projectId: String,
        request: Binding<DealResolution?>,
        zoom: (namespace: Namespace.ID, sourceID: (DealResolution) -> String)? = nil
    ) -> some View {
        modifier(DealResolver(projectId: projectId, request: request, zoom: zoom))
    }
}

private struct DealResolver: ViewModifier {
    let projectId: String
    @Binding var request: DealResolution?
    let zoom: (namespace: Namespace.ID, sourceID: (DealResolution) -> String)?

    private func source(for resolution: DealResolution) -> ZoomSource? {
        zoom.map { ZoomSource(namespace: $0.namespace, id: $0.sourceID(resolution)) }
    }

    @Environment(ProjectDashboardStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Waiting on a yes — bulk accept and pass.
    @State private var confirming: DealResolution?
    @State private var noteRecipients: NoteRecipients?
    @State private var redlineDeal: SellsideDeal?
    @State private var isPromptingForCim = false
    @State private var isUploadingCim = false
    @State private var toast: String?
    @State private var failure: Failure?

    private struct NoteRecipients: Identifiable {
        let deals: [SellsideDeal]
        var id: String { deals.map(\.id).joined(separator: ",") }
    }

    struct Failure: Identifiable {
        let title: String
        let message: String
        var id: String { title + message }
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, request in
                guard let request else { return }
                self.request = nil
                start(request)
            }
            .alert(confirmTitle, isPresented: confirmBinding, presenting: confirming) { resolution in
                switch resolution {
                case .accept(let deals):
                    Button(BulkAcceptCopy(deals: deals).confirm) { run(resolution) }
                case .pass(let deals):
                    Button(PassCopy(deals: deals).confirm, role: .destructive) { run(resolution) }
                default:
                    EmptyView()
                }
                Button("Cancel", role: .cancel) {}
            } message: { resolution in
                Text(confirmMessage(resolution))
            }
            // The waived-CIM guard (`toggleCimModal`). The web routes to
            // project setup; mobile opens its own upload sheet.
            .alert("Upload CIM & Summary Materials", isPresented: $isPromptingForCim) {
                Button("Upload CIM") { isUploadingCim = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You have not yet uploaded a CIM file. Upload one to share it with members.")
            }
            .sheet(item: $noteRecipients) { recipients in
                CIMNoteSheet(projectId: projectId, deals: recipients.deals) { message in
                    showToast(title: "CIM Sent", message)
                }
                .zooming(from: source(for: .shareCim(recipients.deals)))
            }
            .sheet(isPresented: $isUploadingCim) {
                UploadCIMSheet(projectId: projectId)
            }
            .fullScreenCover(item: $redlineDeal) { deal in
                RedlineEditorSheet(projectId: projectId, deal: deal)
                    .zooming(from: source(for: .reviewRedlines(deal)))
            }
            .alert(failure?.title ?? "", isPresented: failureBinding, presenting: failure) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
            .overlay(alignment: .top) {
                if let toast {
                    Text(toast)
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.horizontal, 24)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .animation(.snappy, value: toast)
    }

    // MARK: Flow

    private func start(_ resolution: DealResolution) {
        switch resolution {
        case .accept(let deals):
            // A single accept goes straight through on the web; only the
            // bulk path asks first.
            if deals.count == 1 { run(resolution) } else { confirming = resolution }
        case .pass:
            confirming = resolution
        case .shareCim(let deals):
            if store.dashboard(for: projectId)?.project.cimType == .waive {
                isPromptingForCim = true
            } else {
                noteRecipients = NoteRecipients(deals: deals)
            }
        case .reviewRedlines(let deal):
            redlineDeal = deal
        }
    }

    private func run(_ resolution: DealResolution) {
        Task {
            do {
                switch resolution {
                case .accept(let deals):
                    let updates = try await store.approveAccess(deals.map(\.id), on: projectId)
                    showToast(BulkAcceptCopy.success(count: max(updates.count, deals.count),
                                                     referralSources: updates.map(\.referralSource)))
                case .pass(let deals):
                    try await store.rejectAccess(deals.map(\.id), on: projectId)
                    showToast(title: "Members Passed On", PassCopy.success(count: deals.count))
                default:
                    return
                }
                Haptics.success()
            } catch {
                Haptics.error()
                switch resolution {
                case .accept: failure = Failure(title: "Couldn't accept", message: "Could not approve access.")
                case .pass(let deals):
                    failure = Failure(title: "Couldn\u{2019}t pass on \(deals.count) member\(deals.count == 1 ? "" : "s")",
                                      message: "No changes were made.")
                default: break
                }
            }
        }
    }

    // MARK: Feedback

    /// The web's growler, as a capsule that drops in and leaves.
    private func showToast(title: String? = nil, _ message: String) {
        let text = [title, message].compactMap { $0 }.joined(separator: "\n")
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == text { toast = nil }
        }
    }

    private var confirmTitle: String {
        switch confirming {
        case .accept(let deals)?: BulkAcceptCopy(deals: deals).title
        case .pass(let deals)?: PassCopy(deals: deals).title
        default: ""
        }
    }

    /// The web bolds the key clause; an alert can't, so the markers go.
    private func confirmMessage(_ resolution: DealResolution) -> String {
        let markdown: String
        switch resolution {
        case .accept(let deals): markdown = BulkAcceptCopy(deals: deals).message
        case .pass(let deals): markdown = PassCopy(deals: deals).message
        default: markdown = ""
        }
        return markdown.replacingOccurrences(of: "**", with: "")
    }

    private var confirmBinding: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private var failureBinding: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }
}
