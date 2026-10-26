//
//  OutreachStepViews.swift
//  Axial Mobile
//

import SwiftUI

// MARK: - Sharing Settings

/// Sharing Settings — sharing-settings-step.component.ts: Preferences,
/// Suppression, Sharing Method (or Approval Settings), Referrals.
struct SharingSettingsStepView: View {
    @Environment(ProjectSetupSession.self) private var session
    @State private var isEditingPreferences = false

    var body: some View {
        @Bindable var session = session
        let form = $session.form.sharingSettings

        if !form.wrappedValue.canManuallyShare {
            SetupNotice(style: .info, title: "SmartShare",
                        message: "Your deal is automatically marketed to relevant members on your behalf.",
                        bullets: ["An anonymized teaser is automatically shared to relevant members on your behalf",
                                  "Tailor which members are targeted using the settings below",
                                  "Discoverable across Axial's online sites, while preserving anonymity"])
        }

        if session.context.account.canUseAdvancedFilters {
            SetupSegment(title: "Preferences",
                         description: "Tell us your preferences for members you want to target for this deal.") {
                AudienceReachCard(filters: form.wrappedValue.advancedFilters)
                HStack(spacing: 8) {
                    Button {
                        isEditingPreferences = true
                    } label: {
                        Label("Add Preference", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    if form.wrappedValue.hasPreferences {
                        Button("Reset") { form.wrappedValue.resetPreferences() }
                            .controlSize(.small)
                    }
                }
                if form.wrappedValue.hasPreferences {
                    SetupChipList(items: form.wrappedValue.preferenceLabels.map { ($0, $0) }, palette: .plain) { label in
                        removePreference(label, form: form)
                    }
                }
            }
            .sheet(isPresented: $isEditingPreferences) {
                PreferenceSheet(form: form)
            }
        }

        SuppressionSegment(entries: form.blockedCounterparties)

        if form.wrappedValue.canManuallyShare {
            SetupSegment(title: "Sharing Method", description: "Select your sharing method.") {
                SetupRadioGroup(label: nil, choices: OutreachOptions.sharingModes,
                                selection: Binding(get: { form.wrappedValue.sharingMode },
                                                   set: { if let mode = $0 { form.wrappedValue.setSharingMode(mode) } }),
                                field: "sharingSettings.sharingMode")
                HStack(spacing: 6) {
                    Text("Inbound Inquiry").font(.subheadline.weight(.medium))
                    InfoButton(text: OutreachOptions.inboundInquiryTooltip)
                    Spacer()
                    Toggle("Inbound Inquiry", isOn: form.requiresApproval)
                        .labelsHidden()
                        .tint(AxialColor.brandPrimary)
                }
                .padding(.leading, 4)
                .opacity(form.wrappedValue.sharingMode == "manual" ? 1 : 0.5)
            }
        } else {
            SetupSegment(title: "Approval Settings") {
                SetupToggleRow(title: "Require approval when members pursue",
                               detail: "When enabled and a member pursues your anonymized teaser, your identity, custom teaser, and NDA are not shared. You will need to approve them before Axial shares further details.",
                               isOn: form.requiresApproval)
                SetupNotice(style: .neutral,
                            message: "You can still pre-approve specific members at any time to give them instant access to your identity, custom teaser, and NDA when they pursue.")
            }
        }

        SetupSegment(title: "Referrals",
                     description: "Let contacted members refer your deal — only qualified recipients can express interest in it.") {
            SetupRadioGroup(label: nil, choices: OutreachOptions.referral,
                            selection: Binding(get: { form.wrappedValue.canHaveReferralLinks },
                                               set: { form.wrappedValue.canHaveReferralLinks = $0 ?? "no" }),
                            field: "sharingSettings.can_have_referral_links")
        }
    }

    /// A chip with an item removes just that; an "All" chip clears the list.
    private func removePreference(_ label: String, form: Binding<SharingSettingsForm>) {
        let value = label.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if label.hasPrefix("Company Type:") {
            if value == "All Company Types" { form.wrappedValue.companyTypes = [] }
            else if let code = OutreachOptions.companyTypes.first(where: { $0.label == value })?.value {
                form.wrappedValue.companyTypes.removeAll { $0 == code }
            }
        } else if label.hasPrefix("Capital Source:") {
            if value == "All Capital Sources" { form.wrappedValue.capitalSources = [] }
            else if let code = OutreachOptions.capitalSources.first(where: { $0.label == value })?.value {
                form.wrappedValue.capitalSources.removeAll { $0 == code }
            }
        } else if label.hasPrefix("Acquirer Type:") {
            form.wrappedValue.acquirerType = nil
        } else if label.hasPrefix("Minimum Closed Deals:") {
            form.wrappedValue.minimumClosedDeals = nil
        } else if label.hasPrefix("Location:") {
            var geography = form.wrappedValue.geography ?? []
            geography.removeAll { Geography.label(forID: $0) == value }
            form.wrappedValue.geography = geography.isEmpty ? nil : geography
        }
    }
}

/// "Member Reach" — `POST /intents/{id}/sellside-metrics` with the work in
/// progress filters, debounced 300 ms.
private struct AudienceReachCard: View {
    let filters: JSONValue
    @Environment(ProjectSetupSession.self) private var session
    @Environment(APIClient.self) private var apiClient
    @State private var counts: (filtered: Int, total: Int)?
    @State private var isLoading = true
    @State private var refused = false

    /// The ×1.1 always applies — `isFlexible` is never bound. Web quirk.
    private var percent: Int {
        guard let counts, counts.total > 0 else { return 0 }
        let base = min(max(Double(counts.filtered) / Double(counts.total) * 100, 0), 100)
        return min(100, Int((base * 1.1).rounded()))
    }

    private var countLabel: String {
        let n = counts?.filtered ?? 0
        switch n {
        case 0: return "No members meet your criteria"
        case 1: return "1 member meets your criteria"
        case 2...9: return "\(n) members meet your criteria"
        case 10..<150: return "\(n / 10 * 10)+ members meet your criteria"
        default: return "\(n / 50 * 50)+ members meet your criteria"
        }
    }

    private var barColor: Color {
        switch percent {
        case ...49: AxialColor.error
        case ...79: TagPalette.yellow.foreground
        default: AxialColor.brandPrimary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Member Reach").font(.subheadline.weight(.semibold))
                InfoButton(text: "Each preference reduces your member reach.")
            }
            if refused {
                let dealDetailsIncomplete = session.completion.incompleteSteps.contains { $0.section == .dealDetails }
                SetupNotice(style: .info,
                            title: dealDetailsIncomplete ? "Not enough deal details" : "Project not complete",
                            message: dealDetailsIncomplete
                                ? "Complete Deal Details to determine how many members meet your criteria."
                                : "Complete the project to determine how many members meet your criteria.")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("\(percent)%")
                            .font(.title.weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                    Text(countLabel)
                        .font(.footnote)
                        .foregroundStyle((counts?.filtered ?? 0) == 0 ? AxialColor.errorText : AxialColor.textSecondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AxialColor.layer3)
                        Capsule().fill(barColor).frame(width: proxy.size.width * CGFloat(percent) / 100)
                    }
                }
                .frame(height: 8)
                .animation(.easeOut(duration: 0.3), value: percent)
            }
        }
        .padding(12)
        .background(AxialColor.layer2, in: RoundedRectangle(cornerRadius: 10))
        .task(id: filters) {
            isLoading = true
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await fetch()
        }
    }

    private func fetch() async {
        var body = session.intent.removingKeys(["documents"])
        body.set(filters, at: "advanced_filters")
        do {
            let response: JSONValue = try await apiClient.post("intents/\(session.intentId)/sellside-metrics", body: body)
            counts = (response["filtered_matches"]?.int ?? 0, response["total_matches"]?.int ?? 0)
            refused = false
        } catch APIError.server(409, _, _) {
            refused = true
        } catch is CancellationError {
            return
        } catch {
            counts = nil
            refused = false
        }
        isLoading = false
    }
}

/// "Suppression": a chips input that rejects invalid entries with the
/// web's messages, shown in place of the helper for three seconds.
private struct SuppressionSegment: View {
    @Binding var entries: [String]
    @State private var draft = ""
    @State private var rejection: String?
    @Environment(ProjectSetupSession.self) private var session

    var body: some View {
        let invalidExisting = Set(entries.compactMap(Counterparty.validationError(for:)))
        SetupSegment(title: "Suppression", description: "Tell us who must not receive this deal") {
            VStack(alignment: .leading, spacing: 8) {
                SetupFieldLabel(text: "Don't share with:")
                if !entries.isEmpty {
                    SetupChipList(items: entries.map { ($0, $0) },
                                  palette: .plain) { entry in entries.removeAll { $0 == entry } }
                }
                TextField("Enter an email address, email domain, or website", text: $draft, axis: .vertical)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(commit)
                    .onChange(of: draft) { _, text in
                        if text.contains(",") || text.contains("\n") { commit() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AxialColor.border))
                if let rejection {
                    SetupFieldError(message: rejection)
                } else if !invalidExisting.isEmpty {
                    SetupFieldError(message: invalidExisting.sorted().joined(separator: "\n"))
                } else {
                    SetupHelperText(text: "Press 'Return' after each entry, or paste a list — one per line. These changes only impact this project.")
                }
            }
            SetupNotice(style: .neutral,
                        message: "To apply suppression at the account level for all projects, add suppression in company settings.")
        }
        .animation(.easeOut(duration: 0.2), value: rejection)
    }

    private func commit() {
        let candidates = Counterparty.entries(from: draft)
        draft = ""
        var errors: [String] = []
        for candidate in candidates where !entries.contains(candidate) {
            if let error = Counterparty.validationError(for: candidate) {
                if !errors.contains(error) { errors.append(error) }
            } else {
                entries.append(candidate)
            }
        }
        guard !errors.isEmpty else { return }
        Haptics.error()
        rejection = errors.joined(separator: "\n")
        Task {
            try? await Task.sleep(for: .seconds(3))
            rejection = nil
        }
    }
}

/// "Select a Preference Type" — the Add Preference popover's menus, as a
/// sheet with one page each. Edits apply live.
private struct PreferenceSheet: View {
    @Binding var form: SharingSettingsForm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CompanyTypeCapitalSourcePage(form: $form)
                } label: { menuRow("Company Type / Capital Source", "Select one (mutually exclusive)") }
                NavigationLink {
                    RadioPage(title: "Acquirer Type", choices: OutreachOptions.acquirerTypes,
                              selection: Binding(get: { form.acquirerType ?? "" },
                                                 set: { form.acquirerType = $0.isEmpty ? nil : $0 }),
                              onClear: { form.acquirerType = nil })
                } label: { menuRow("Acquirer Type", "Strategic, Financial, or Both") }
                NavigationLink {
                    // Web quirk, mirrored: "Any Amount" sets "0", which still
                    // shows a chip until the step is re-entered.
                    RadioPage(title: "Minimum Closed Deals", choices: OutreachOptions.minimumClosedDeals,
                              selection: Binding(get: { form.minimumClosedDeals ?? "0" },
                                                 set: { form.minimumClosedDeals = $0 }),
                              onClear: { form.minimumClosedDeals = nil })
                } label: { menuRow("Minimum Closed Deals", "Filter by transaction experience") }
                NavigationLink {
                    LocationPage(geography: $form.geography)
                } label: { menuRow("Location", "Country, Region, or State") }
            }
            .navigationTitle("Select a Preference Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func menuRow(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.medium))
            Text(subtitle).font(.footnote).foregroundStyle(AxialColor.textSecondary)
        }
    }
}

private struct RadioPage: View {
    let title: String
    let choices: [SetupChoice<String>]
    @Binding var selection: String
    let onClear: () -> Void

    var body: some View {
        List(choices) { choice in
            Button {
                Haptics.selection()
                selection = choice.value
            } label: {
                HStack {
                    Image(systemName: selection == choice.value ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selection == choice.value ? AxialColor.brandPrimary : AxialColor.textPlaceholder)
                    Text(choice.label).foregroundStyle(AxialColor.textPrimary)
                }
            }
        }
        .navigationTitle(title)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Clear", action: onClear) } }
    }
}

/// One or the other: picking on one tab clears the other's selection.
private struct CompanyTypeCapitalSourcePage: View {
    @Binding var form: SharingSettingsForm
    @State private var tab = 0

    var body: some View {
        List {
            Section {
                SetupNotice(style: .warning,
                            message: "You can filter by Company Type or Capital Source, but not both. Selecting one will clear the other.")
                    .listRowInsets(EdgeInsets())
                Picker("Filter", selection: $tab) {
                    Text("Company Type").tag(0)
                    Text("Capital Source").tag(1)
                }
                .pickerStyle(.segmented)
            }
            Section {
                let choices = tab == 0 ? OutreachOptions.companyTypes : OutreachOptions.capitalSources
                let selected = tab == 0 ? form.companyTypes : form.capitalSources
                checkRow("Select All", state: selected.count == choices.count ? .on : selected.isEmpty ? .off : .mixed) {
                    set(selected.count == choices.count ? [] : choices.map(\.value))
                }
                ForEach(choices) { choice in
                    checkRow(choice.label, state: selected.contains(choice.value) ? .on : .off) {
                        set(selected.contains(choice.value) ? selected.filter { $0 != choice.value } : selected + [choice.value])
                    }
                }
            }
        }
        .navigationTitle("Company Type / Capital Source")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { form.companyTypes = []; form.capitalSources = [] }
            }
        }
        .onAppear {
            // If both somehow hold values, capital source wins.
            if !form.capitalSources.isEmpty {
                tab = 1
                if !form.companyTypes.isEmpty { form.companyTypes = [] }
            }
        }
    }

    private enum CheckState { case on, off, mixed }

    private func set(_ values: [String]) {
        Haptics.selection()
        if tab == 0 { form.companyTypes = values; form.capitalSources = [] }
        else { form.capitalSources = values; form.companyTypes = [] }
    }

    private func checkRow(_ label: String, state: CheckState, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: state == .on ? "checkmark.square.fill" : state == .mixed ? "minus.square.fill" : "square")
                    .foregroundStyle(state == .off ? AxialColor.textPlaceholder : AxialColor.brandPrimary)
                Text(label).foregroundStyle(AxialColor.textPrimary)
            }
        }
    }
}

/// `location-menu`: US and Canada by region, then international regions,
/// with search. Saved rolled up (all of a region → the region's id).
private struct LocationPage: View {
    @Binding var geography: [Int]?
    @State private var query = ""
    @State private var expanded: Set<Int> = []

    private var leaves: Set<Int> { Geography.leaves(for: geography ?? []) }

    var body: some View {
        List {
            ForEach(filteredLocal) { country in
                Section {
                    tierRow(country, depth: 0)
                    if isExpanded(country) {
                        ForEach(country.children) { region in
                            tierRow(region, depth: 1)
                            if isExpanded(region) {
                                ForEach(region.children) { leaf in tierRow(leaf, depth: 2) }
                            }
                        }
                    }
                }
            }
            let international = filteredInternational
            if !international.isEmpty {
                Section {
                    let node = Geography.TierNode(id: -1, label: "International", children: international)
                    tierRow(node, depth: 0, expandable: false)
                    ForEach(international) { leaf in tierRow(leaf, depth: 1) }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search locations")
        .navigationTitle("Location")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Clear") { geography = nil } }
        }
    }

    private func isExpanded(_ node: Geography.TierNode) -> Bool {
        !query.isEmpty || expanded.contains(node.id)
    }

    private var filteredLocal: [Geography.TierNode] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Geography.localTiers }
        return Geography.localTiers.compactMap { country in
            if country.label.lowercased().contains(q) { return country }
            let regions = country.children.compactMap { region -> Geography.TierNode? in
                if region.label.lowercased().contains(q) { return region }
                let leaves = region.children.filter { $0.label.lowercased().contains(q) }
                return leaves.isEmpty ? nil : Geography.TierNode(id: region.id, label: region.label, children: leaves)
            }
            return regions.isEmpty ? nil : Geography.TierNode(id: country.id, label: country.label, children: regions)
        }
    }

    private var filteredInternational: [Geography.TierNode] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty || "international".contains(q) { return Geography.internationalTiers }
        return Geography.internationalTiers.filter { $0.label.lowercased().contains(q) }
    }

    private func tierRow(_ node: Geography.TierNode, depth: Int, expandable: Bool = true) -> some View {
        let ids = Set(node.leafIDs)
        let selected = ids.intersection(leaves)
        let state = selected.count == ids.count ? 2 : selected.isEmpty ? 0 : 1
        return HStack(spacing: 12) {
            Button {
                Haptics.selection()
                var next = leaves
                if state == 2 { next.subtract(ids) } else { next.formUnion(ids) }
                let rolled = Geography.rolledUp(next)
                geography = rolled.isEmpty ? nil : rolled
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: state == 2 ? "checkmark.square.fill" : state == 1 ? "minus.square.fill" : "square")
                        .foregroundStyle(state == 0 ? AxialColor.textPlaceholder : AxialColor.brandPrimary)
                    Text(node.label)
                        .fontWeight(depth == 0 ? .semibold : .regular)
                        .foregroundStyle(AxialColor.textPrimary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if expandable, !node.children.isEmpty, query.isEmpty {
                Button {
                    withAnimation(.snappy) {
                        if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded.contains(node.id) ? 90 : 0))
                        .foregroundStyle(AxialColor.textPlaceholder)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, CGFloat(depth) * 20)
    }
}

// MARK: - Marketing Settings

/// Marketing Settings (`messaging`) — Deal Team, Outreach Note, Follow-Up
/// Note.
struct MessagingStepView: View {
    @Environment(ProjectSetupSession.self) private var session
    @Environment(SetupRouter.self) private var router
    @State private var tosPulse = false
    private typealias F = MessagingForm.Field

    var body: some View {
        @Bindable var session = session
        let form = $session.form.messaging
        let members = session.members

        SetupSegment(title: "Deal Team", hasError: session.segmentHasError([F.assignedToUser])) {
            VStack(alignment: .leading, spacing: 6) {
                SetupSearchPickerRow(label: "Primary Contact",
                                     choices: members.map { .init(value: $0.id, label: $0.fullName) },
                                     selection: Binding(get: { session.member(form.wrappedValue.assignedToUser)?.id ?? form.wrappedValue.assignedToUser },
                                                        set: { form.wrappedValue.setPrimaryContact($0) }),
                                     field: F.assignedToUser, placeholder: "Select a team member")
                SetupHelperText(text: "Select a team member to represent your team on this deal. Their name and profile will appear with the deal headline for buyside members, and they'll receive all deal messages and notifications.")
            }
            if session.unsignedPrimaryContact != nil {
                SetupNotice(style: .warning,
                            message: "This user has not signed the Terms of Service. To activate this project, please reassign this project or have them accept the ToS.")
                    .scaleEffect(tosPulse ? 1.03 : 1)
                    .animation(.spring(duration: 0.3, bounce: 0.5).repeatCount(3, autoreverses: true), value: tosPulse)
            }
            MemberPickerRow(label: "Additional Contacts",
                            helper: "Select additional team members to receive all deal messages and notifications.",
                            placeholder: "Select team members", selection: form.additionalContacts,
                            field: "messaging.additional_contacts", excluding: form.wrappedValue.assignedToUser)
        }
        .onAppear {
            if router.pulseTosNotice {
                router.pulseTosNotice = false
                Task { try? await Task.sleep(for: .milliseconds(500)); tosPulse.toggle() }
            }
        }

        SetupSegment(title: "Outreach Note",
                     description: "This note will be sent with an Axial anonymized teaser containing data from Deal Details.") {
            MemberPickerRow(label: "Cc", helper: "Select team members to be copied on all outbound outreach notes.",
                            placeholder: "Select team members", selection: form.teaserCc, field: "messaging.teaser.cc-emails")
            MessageEditor(label: "Message", text: form.teaserMessage, field: "messaging.teaser.message")
            SetupNotice(style: .neutral, message: "Identifying details remain hidden until members pursue.")
        }

        SetupSegment(title: "Follow-Up Note",
                     description: "Automatically send a follow-up note to contacted members after a set number of business days.") {
            SetupToggleRow(title: "Enable follow-up note", isOn: form.followUpEnabled)
            VStack(alignment: .leading, spacing: 12) {
                MessageEditor(label: "Message", text: form.followUpMessage, field: "messaging.follow_up_note.message")
                HStack(spacing: 8) {
                    Text("Send")
                    Picker("Days", selection: form.followUpDays) {
                        ForEach(OutreachOptions.followUpDays) { Text($0.label).tag($0.value) }
                    }
                    .pickerStyle(.menu)
                    Text("business days after initial teaser share")
                }
                .font(.subheadline)
                SetupNotice(style: .neutral, message: "Identifying details remain hidden until members pursue.")
            }
            // Dimmed when off, but not disabled — as on the web.
            .opacity(form.wrappedValue.followUpEnabled ? 1 : 0.5)
        }
        .id("follow-up-note")
    }
}

/// A member multi-select, shown as chips — CC lists and additional contacts.
struct MemberPickerRow: View {
    let label: String
    let helper: String
    let placeholder: String
    @Binding var selection: [String]
    let field: SetupFieldKey
    var excluding: String?

    @Environment(ProjectSetupSession.self) private var session
    @State private var isPicking = false

    var body: some View {
        let names = selection.compactMap { session.member($0)?.fullName }
        SetupPickerRow(label: label, field: field, summary: names, placeholder: placeholder, helper: helper) {
            isPicking = true
        }
        .sheet(isPresented: $isPicking) {
            SetupMultiPicker(title: label.trimmingCharacters(in: CharacterSet(charactersIn: ":")),
                             choices: session.members.filter { !$0.matches(excluding) }
                                 .map { .init(value: $0.id, label: $0.fullName) },
                             selection: Binding(
                                 get: { selection.map { id in session.member(id)?.id ?? id } },
                                 set: { selection = $0 }),
                             searchable: session.members.count > 8)
        }
    }
}

/// `axl-token-textarea`: the message with its merge tags as plain
/// `{tokens}`, plus the one insert button the web has.
struct MessageEditor: View {
    let label: String
    @Binding var text: String
    let field: SetupFieldKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SetupTextEditor(label: label, text: $text, field: field, minHeight: 140)
            Button {
                Haptics.selection()
                text = text.isEmpty ? MergeTag.recipientFirstName : text + " " + MergeTag.recipientFirstName
            } label: {
                Label("Add Recipient's First Name", systemImage: "person.crop.circle.badge.plus")
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Shareable Deal Link

/// "Deal Link" — the shareable link, for active projects only.
struct DealLinkStepView: View {
    @Environment(ProjectSetupSession.self) private var session
    @State private var copied = false
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        SetupSegment(title: "Deal Link",
                     description: "Consolidate interest on Axial by sharing this deal to anyone you choose.") {
            Button {
                Task { await copy() }
            } label: {
                if isWorking {
                    ProgressView()
                } else {
                    Label(copied ? "Link Copied" : "Copy Link", systemImage: copied ? "checkmark" : "link")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)
            if let error {
                SetupFieldError(message: error)
            }
            SetupNotice(style: .neutral,
                        message: "Non-Axial members who pursue this deal through the shareable deal link are exempt from Axial's success fee.")
        }
    }

    private func copy() async {
        isWorking = true
        defer { isWorking = false }
        do {
            UIPasteboard.general.string = try await session.dealLink()
            Haptics.success()
            withAnimation { copied = true }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copied = false }
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
        }
    }
}
