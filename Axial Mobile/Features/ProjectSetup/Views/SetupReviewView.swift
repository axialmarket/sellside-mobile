//
//  SetupReviewView.swift
//  Axial Mobile
//

import SwiftUI

/// "Review & Share" — the web's confirmation panel, pushed full screen. Swipe
/// back returns to wherever review was opened from. Each row's pencil goes
/// to the step that owns it.
struct SetupReviewView: View {
    let onExit: (SetupExit) -> Void

    @Environment(ProjectSetupSession.self) private var session
    @Environment(SetupRouter.self) private var router

    @State private var isConfirmingApproval = false
    @State private var progress: ShareProgress?
    @State private var shareError: String?
    @State private var isSendingTest = false
    @State private var toast: String?

    enum ShareProgress: Equatable {
        case sharing(String)
        case approval
    }

    var body: some View {
        let payload = session.reviewPayload
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.form.companyBasics.internalName.isEmpty ? "Untitled Project" : session.form.companyBasics.internalName)
                        .font(.subheadline)
                        .foregroundStyle(AxialColor.textSecondary)
                    Text(session.context.account.name ?? "<Company Name>")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AxialColor.textPrimary)
                }

                if session.context.isInMarket {
                    changesSection
                }
                summarySection(payload)
                financialsSection
                if session.context.isCapitalRaise {
                    capitalSection
                }
                documentsSection(payload)
                sharingSection(payload)
                messagesSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AxialColor.layer2)
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if let progress {
                ShareProgressOverlay(progress: progress)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: progress)
        .animation(.easeOut(duration: 0.25), value: toast)
        .navigationTitle(session.reviewLabel)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(progress != nil)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    Task { await sendTest() }
                } label: {
                    if isSendingTest { ProgressView() } else { Text("Send Yourself a Test") }
                }
                .tint(AxialColor.textPrimary)
                .disabled(isSendingTest || progress != nil)
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button(primaryLabel) { primaryAction() }
                    .buttonStyle(.borderedProminent)
                    .tint(AxialColor.brandPrimary)
                    .disabled(progress != nil)
                    .accessibilityIdentifier("setup-share")
            }
        }
        .alert("Project Requires Approval", isPresented: $isConfirmingApproval) {
            Button("Submit For Approval") { Task { await share(submitForApproval: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isSmartShare
                 ? "An Axial representative needs to review this project in order to ensure best results. Once approved, your teaser will be shared."
                 : "An Axial representative needs to review this project in order to ensure best results. Once approved, your recommendation list will be ready to review.")
        }
        .alert("Couldn't save the project", isPresented: errorBinding, presenting: shareError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    // MARK: CTAs

    private var isSmartShare: Bool { session.form.sharingSettings.sharingMode == "smartshare" }

    /// The live form's sharing mode picks the label; the title comes from
    /// the saved one. Same split as the web.
    private var primaryLabel: String {
        if session.context.isInMarket { return "Save Project" }
        return isSmartShare ? "Share Deal Now" : "Manually Review Members"
    }

    private func primaryAction() {
        if !session.context.isInMarket, session.needsApproval {
            isConfirmingApproval = true
        } else {
            Task { await share(submitForApproval: false) }
        }
    }

    private func share(submitForApproval: Bool) async {
        if session.context.isInMarket {
            progress = .sharing("Saving…")
        } else if submitForApproval {
            progress = .approval
        } else {
            progress = .sharing(isSmartShare ? "Sharing deal now with SmartShare..." : "Loading Recommendations...")
        }
        let started = Date.now
        do {
            let outcome = try await session.share(submitForApproval: submitForApproval)
            if submitForApproval {
                // Let the review sequence finish (1.5 s a step, three steps,
                // then a beat) before leaving.
                let remaining = 6.0 - Date.now.timeIntervalSince(started)
                if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            }
            Haptics.success()
            switch outcome {
            case .saved: onExit(.saved)
            case .submittedForApproval: onExit(.submittedForApproval)
            case .shared(let smartShare): onExit(.shared(SmartShare: smartShare))
            }
        } catch {
            Haptics.error()
            progress = nil
            shareError = error.localizedDescription
        }
    }

    /// Whole form valid, or nothing is sent.
    private func sendTest() async {
        guard session.completion.isComplete else {
            showToast("Complete all required steps to send a test.")
            return
        }
        isSendingTest = true
        defer { isSendingTest = false }
        do {
            try await session.sendTestMessage()
            Haptics.success()
            showToast("Test message sent successfully")
        } catch {
            Haptics.error()
            showToast("Failed to send test message")
        }
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == text { toast = nil }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })
    }

    private func edit(_ step: SetupStep) {
        router.open(step)
    }

    // MARK: Sections

    private var changesSection: some View {
        let changes = ReviewChanges.changes(from: session.savedPayload, to: session.reviewPayload,
                                            documents: session.form.documents,
                                            canManuallyShare: session.form.sharingSettings.canManuallyShare)
        return ReviewSection(title: "Changes (\(changes.count))") {
            if changes.isEmpty {
                Text("No changes").font(.subheadline).foregroundStyle(AxialColor.textPlaceholder)
            }
            ForEach(changes) { change in
                ReviewRow(name: change.name, onEdit: { edit(change.step) }) { EmptyView() }
            }
        }
    }

    private func summarySection(_ payload: JSONValue) -> some View {
        let form = session.form
        let basics = form.companyBasics
        let contacts = form.messaging.additionalContacts.compactMap { session.member($0)?.fullName }
        return ReviewSection(title: "Summary") {
            ReviewRow(name: "Primary Contact", onEdit: { edit(.messaging) }) {
                ReviewValue(session.member(form.messaging.assignedToUser)?.fullName)
            }
            ReviewRow(name: "Additional Contacts", onEdit: { edit(.messaging) }) {
                if contacts.isEmpty { ReviewValue(nil) }
                else { ReviewTag(ReviewChanges.plural(contacts.count, "Contact"), items: contacts) }
            }
            ReviewRow(name: "Company Website", onEdit: { edit(.companyBasics) }) {
                let site = basics.companyWebsite.trimmingCharacters(in: .whitespaces)
                if site.isEmpty { ReviewValue(nil) }
                else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(site).lineLimit(1).truncationMode(.middle)
                        Text("(Only visible to you)").font(.caption).foregroundStyle(AxialColor.textPlaceholder)
                    }
                    .font(.subheadline)
                }
            }
            ReviewRow(name: "Company HQ", onEdit: { edit(.companyBasics) }) {
                if let hq = Geography.displayName(state: basics.state, country: basics.country, disclosure: basics.disclosure) {
                    Label(hq, systemImage: "globe.americas").font(.subheadline).lineLimit(2)
                } else { ReviewValue(nil) }
            }
            ReviewRow(name: "Industries", onEdit: { edit(.companyBasics) }) {
                if basics.industries.isEmpty { ReviewValue(nil) }
                else {
                    ReviewTag(ReviewChanges.plural(basics.industries.count, "Industry", "Industries"),
                              items: basics.industries.map(\.name))
                }
            }
            if session.context.intentType == "sell_business" {
                ReviewRow(name: "Licenses Required", onEdit: { edit(.companyBasics) }) {
                    if basics.licensesRequired == "yes" {
                        ReviewTag("Yes", items: basics.licenseDetails.isEmpty ? [] : [basics.licenseDetails])
                    } else { ReviewValue(nil) }
                }
            }
            ReviewRow(name: "Real Estate", onEdit: { edit(.companyBasics) }) {
                if basics.realEstateIncluded == "yes" {
                    ReviewTag("Yes", items: basics.realEstateDetails.isEmpty ? [] : [basics.realEstateDetails])
                } else { ReviewValue(nil) }
            }
        }
    }

    private var financialsSection: some View {
        let financials = session.form.financials
        let catalog = session.catalog
        let kpis = financials.committedKPIs.map { row -> String in
            let type = catalog.type(row.financialType)
            let label = catalog.kpi.first { $0.key == row.financialType }?.label ?? type?.label ?? row.financialType
            return "\(label): \(FinancialCellRules.summary(row.value, unit: type?.unit ?? "$"))"
        }
        return ReviewSection(title: "Financials & KPIs") {
            ReviewRow(name: "Historical Metrics", onEdit: { edit(.financials) }) {
                let count = financials.periodic.periodCount
                if count == 0 { ReviewValue(nil) }
                else {
                    ReviewTag("\(count) Year\(count == 1 ? "" : "s") of Financials") {
                        FinancialSummaryTable(rows: financials.periodic.rows, catalog: catalog)
                            .frame(maxWidth: 360)
                    }
                }
            }
            ReviewRow(name: "Current Metrics", onEdit: { edit(.financials) }) {
                if kpis.isEmpty { ReviewValue(nil) }
                else { ReviewTag(ReviewChanges.plural(kpis.count, "Current Metric"), items: kpis) }
            }
            ReviewRow(name: "Valuation Expectation", onEdit: { edit(.financials) }) {
                if let row = financials.valuation.committed, let max = row.maxValue {
                    let label = catalog.type(row.financialType)?.label ?? row.financialType
                    let base = label.hasSuffix(" Multiple") ? String(label.dropLast(" Multiple".count)) : label
                    ReviewValue("\((row.minValue ?? 0).formatted())x - \(max.formatted())x \(base)")
                } else { ReviewValue(nil) }
            }
            ReviewRow(name: "Financial Commentary", onEdit: { edit(.financials) }) {
                if financials.commentary.isEmpty { ReviewValue(nil) }
                else { ReviewTag("Yes", items: [financials.commentary.text]) }
            }
        }
    }

    private var capitalSection: some View {
        let capital = session.form.capitalRaise
        let typeLabel = CapitalOptions.capitalTypes.first { $0.value == capital.capitalType }?.label
        let debt = capital.debtTypes.map(DebtTypes.label)
        let uses = capital.useOfFunds.compactMap { use in CapitalOptions.useOfFunds.first { $0.value == use }?.label }
        return ReviewSection(title: "Capital Raise") {
            ReviewRow(name: "Capital Type", onEdit: { edit(.capitalRaise) }) {
                if let typeLabel {
                    ReviewTag(debt.isEmpty ? typeLabel : "\(typeLabel) (\(ReviewChanges.plural(debt.count, "type")))", items: debt)
                } else { ReviewValue(nil) }
            }
            ReviewRow(name: "Intended Use of Funds", onEdit: { edit(.capitalRaise) }) {
                if uses.isEmpty { ReviewValue(nil) } else { ReviewTag(ReviewChanges.plural(uses.count, "Use"), items: uses) }
            }
            ReviewRow(name: "Total Capital", onEdit: { edit(.capitalRaise) }) {
                ReviewValue(capital.maxRange.map { "$\($0.formatted())M" })
            }
            ReviewRow(name: "Minimum Check Size", onEdit: { edit(.capitalRaise) }) {
                ReviewValue(capital.minRange.map { "$\($0.formatted())M" })
            }
        }
    }

    private func documentsSection(_ payload: JSONValue) -> some View {
        let documents = session.form.documents
        let ndaType = payload["nda_type"]?.string
        return ReviewSection(title: "Documents") {
            ReviewRow(name: "Custom Teaser", onEdit: { edit(.customTeaser) }) {
                ReviewValue(documents.teaser?.filename)
            }
            ReviewRow(name: "NDA", onEdit: { edit(.nda) }) {
                switch ndaType {
                case "axial": Label("Axial Standard NDA", systemImage: "checkmark.seal").font(.subheadline)
                case "custom": ReviewValue(documents.customNDA?.filename)
                case "linked": ReviewValue(payload["linked_nda"]?.string)
                default: ReviewValue(nil)
                }
            }
            ReviewRow(name: "CIM / Summary Materials", onEdit: { edit(.cimSummaryMaterials) }) {
                if payload["cim_type"]?.string == "linked", let link = payload["linked_cim"]?.string {
                    ReviewTag("1 Attachment", items: [link])
                } else if !documents.cimDocuments.isEmpty {
                    ReviewTag(ReviewChanges.plural(documents.cimDocuments.count, "Attachment"),
                              items: documents.cimDocuments.map(\.filename))
                } else { ReviewValue(nil) }
            }
            ReviewRow(name: "Automatic CIM Share", onEdit: { edit(.cimSummaryMaterials) }) {
                EnabledValue(isEnabled: payload["use_cim_smartshare"]?.bool == true)
            }
        }
    }

    private func sharingSection(_ payload: JSONValue) -> some View {
        let sharing = session.form.sharingSettings
        let setting = sharing.setting
        let preferences = sharing.preferenceLabels
        let blocked = sharing.blockedCounterparties
        return ReviewSection(title: "Sharing") {
            ReviewRow(name: "Sharing Method", onEdit: { edit(.sharingSettings) }) {
                if setting == .smartshare {
                    Label("SmartShare", systemImage: "bolt.fill").font(.subheadline).foregroundStyle(AxialColor.brandPrimary)
                } else {
                    Label("Manual Review", systemImage: "checklist").font(.subheadline).foregroundStyle(AxialColor.textSecondary)
                }
            }
            if !(sharing.canManuallyShare && setting == .smartshare) {
                ReviewRow(name: sharing.canManuallyShare ? "Inbound Inquiry" : "Requires Approval",
                          onEdit: { edit(.sharingSettings) }) {
                    EnabledValue(isEnabled: payload["requires_approval"]?.bool == true)
                }
            }
            ReviewRow(name: "Preferences", onEdit: { edit(.sharingSettings) }) {
                if preferences.isEmpty { ReviewValue(nil) }
                else { ReviewTag(ReviewChanges.plural(preferences.count, "Preference"), items: preferences) }
            }
            ReviewRow(name: "Suppression", onEdit: { edit(.sharingSettings) }) {
                if blocked.isEmpty { ReviewValue(nil) }
                else { ReviewTag("\(ReviewChanges.plural(blocked.count, "Member")) Suppressed", items: blocked) }
            }
        }
    }

    private var messagesSection: some View {
        let messaging = session.form.messaging
        let cim = session.form.cim
        return ReviewSection(title: "Message Templates") {
            ReviewRow(name: "Teaser Message", onEdit: { edit(.messaging) }) {
                messageTags(messaging.teaserMessage, default: MessagingForm.teaserDefault, cc: messaging.teaserCc)
            }
            ReviewRow(name: "Follow-Up Note", onEdit: { edit(.messaging) }) {
                if !messaging.followUpEnabled { ReviewValue("Disabled", isMuted: true) }
                else {
                    VStack(alignment: .trailing, spacing: 6) {
                        messageTag(messaging.followUpMessage, default: MessagingForm.followUpDefault)
                        TagCapsule(text: "\(messaging.followUpDays) business days after share", palette: .plain)
                    }
                }
            }
            ReviewRow(name: "CIM Message", onEdit: { edit(.cimSummaryMaterials) }) {
                messageTags(cim.message, default: CIMForm.defaultMessage, cc: cim.ccMembers)
            }
            ReviewRow(name: "Calendar Link", onEdit: { edit(.cimSummaryMaterials) }) {
                ReviewValue(cim.calendarLink.isEmpty ? nil : cim.calendarLink)
            }
        }
    }

    private func messageTags(_ message: String, default defaultMessage: String, cc: [String]) -> some View {
        let names = cc.compactMap { session.member($0)?.fullName }
        return VStack(alignment: .trailing, spacing: 6) {
            messageTag(message, default: defaultMessage)
            if names.isEmpty { TagCapsule(text: "No Members CC'd", palette: .plain, isMuted: true) }
            else { ReviewTag("\(ReviewChanges.plural(names.count, "Member")) CC'd", items: names) }
        }
    }

    @ViewBuilder
    private func messageTag(_ message: String, default defaultMessage: String) -> some View {
        if message.trimmingCharacters(in: .whitespacesAndNewlines) == defaultMessage.trimmingCharacters(in: .whitespacesAndNewlines) {
            ReviewTag("Axial Default Message", items: [message])
        } else {
            ReviewTag("Custom Message", items: [message])
        }
    }
}

// MARK: - Building blocks

private struct ReviewSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AxialColor.textPrimary)
                .padding(.bottom, 10)
            VStack(spacing: 0) {
                content
            }
            .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AxialColor.border))
        }
    }
}

/// `project-setup-confirmation-panel-section-row`: name, value, edit pencil.
private struct ReviewRow<Value: View>: View {
    let name: String
    let onEdit: () -> Void
    @ViewBuilder let value: Value

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AxialColor.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 8)
            value
                .multilineTextAlignment(.trailing)
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AxialColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 14)
        }
    }
}

/// A value, or the faded "None".
private struct ReviewValue: View {
    let text: String?
    var isMuted = false

    init(_ text: String?, isMuted: Bool = false) {
        self.text = text
        self.isMuted = isMuted
    }

    var body: some View {
        Text(text ?? "None")
            .font(.subheadline)
            .foregroundStyle(text == nil || isMuted ? AxialColor.textPlaceholder : AxialColor.textPrimary)
            .lineLimit(2)
            .truncationMode(.middle)
    }
}

private struct EnabledValue: View {
    let isEnabled: Bool

    var body: some View {
        if isEnabled {
            Label("Enabled", systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(AxialColor.success)
        } else {
            ReviewValue("Disabled", isMuted: true)
        }
    }
}

/// A small tag that opens what it summarises — the web's hover popovers.
private struct ReviewTag<Detail: View>: View {
    let text: String
    let detail: Detail
    @State private var isShowing = false

    init(_ text: String, @ViewBuilder detail: () -> Detail) {
        self.text = text
        self.detail = detail()
    }

    var body: some View {
        Button {
            isShowing = true
        } label: {
            TagCapsule(text: text, palette: .blue)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowing) {
            ScrollView {
                detail.padding(14)
            }
            .frame(maxWidth: 360, maxHeight: 320)
            .presentationCompactAdaptation(.popover)
        }
    }
}

private extension ReviewTag where Detail == ReviewList {
    init(_ text: String, items: [String]) {
        self.text = text
        self.detail = ReviewList(items: items)
    }
}

private struct ReviewList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item)
                    .font(.footnote)
                    .foregroundStyle(AxialColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The share flow's backdrop, or the Approval Loading sequence —
/// "How we review your project".
private struct ShareProgressOverlay: View {
    let progress: SetupReviewView.ShareProgress
    @State private var activeStep = 0

    private let steps: [(icon: String, title: String, detail: String)] = [
        ("list.clipboard", "Running Initial Checks", "We will make sure your project is ready to go live!"),
        ("touchid", "Checking for PII", "We will protect your identifying details from buyside members pre-pursuit."),
        ("doc.text", "Evaluating CIM", "We will make sure your CIM is complete and ready for buyside consumption."),
    ]

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            switch progress {
            case .sharing(let text):
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(text).font(.headline).foregroundStyle(AxialColor.textPrimary)
                }
            case .approval:
                VStack(alignment: .leading, spacing: 18) {
                    Text("How we review your project").font(.title2.weight(.bold))
                    Text("Our team will review the following items to ensure that your project is ready to go to market.")
                        .font(.subheadline)
                        .foregroundStyle(AxialColor.textSecondary)
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle().fill(index <= activeStep ? AxialColor.brandSubtle : AxialColor.layer3)
                                    .frame(width: 44, height: 44)
                                if index == activeStep {
                                    ProgressView()
                                } else {
                                    Image(systemName: index < activeStep ? "checkmark" : step.icon)
                                        .foregroundStyle(index < activeStep ? AxialColor.success : AxialColor.textSecondary)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title).font(.subheadline.weight(.semibold))
                                Text(step.detail).font(.footnote).foregroundStyle(AxialColor.textSecondary)
                            }
                        }
                        .opacity(index <= activeStep ? 1 : 0.5)
                    }
                }
                .padding(24)
                .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 20))
                .padding(24)
                .task {
                    // Placeholder timers, as on the web: 1.5 s a step.
                    for step in 1...3 {
                        try? await Task.sleep(for: .milliseconds(1500))
                        withAnimation { activeStep = step }
                    }
                }
            }
        }
    }
}
