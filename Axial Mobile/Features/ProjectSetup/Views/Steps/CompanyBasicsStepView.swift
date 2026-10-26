//
//  CompanyBasicsStepView.swift
//  Axial Mobile
//

import SwiftUI

/// Company Basics — company-basics-section.html and its seven segments, in
/// the web's order.
struct CompanyBasicsStepView: View {
    @Environment(ProjectSetupSession.self) private var session
    @State private var isPickingIndustries = false
    @State private var isPickingEndMarkets = false
    @State private var isConfirmingClearIndustries = false

    private typealias F = CompanyBasicsForm.Field

    var body: some View {
        @Bindable var session = session
        let form = $session.form.companyBasics
        let context = session.context

        projectDetails(form)
        industry(form)
        roleMandate(form, isCapitalRaise: context.isCapitalRaise)
        location(form)
        internalDetails(form, isSellBusiness: context.intentType == "sell_business")
        attributes(form, isSellBusiness: context.intentType == "sell_business")
        endMarkets(form)
    }

    // MARK: Project & Company Details

    private func projectDetails(_ form: Binding<CompanyBasicsForm>) -> some View {
        SetupSegment(title: "Project & Company Details",
                     hasError: session.segmentHasError([F.internalName, F.headline, F.description])) {
            SetupTextField(label: "Internal Project Name", text: form.internalName, field: F.internalName,
                           placeholder: "Untitled Project",
                           helper: "This is for internal use only, buyside members will not be able to see the name of your project.")
            SetupTextField(label: "External Headline", text: form.headline, field: F.headline,
                           placeholder: "Enter an external headline",
                           helper: form.wrappedValue.headlineCountText)
            SetupRichTextEditor(label: "Company Description", value: form.description, field: F.description,
                                placeholder: "Enter a description",
                                counter: form.wrappedValue.descriptionCountText,
                                counterIsValid: form.wrappedValue.description.visibleLength >= CompanyBasicsForm.descriptionMin,
                                minHeight: 160)
            SetupNotice(style: .neutral,
                        message: "Axial enhances your headline and description to maximize credible member interest for each opportunity.")
            Link("Learn how it works.",
                 destination: URL(string: "https://guide.axial.net/docs/how-teaser-headlines-and-descriptions-are-optimized-on-axial")!)
                .font(.footnote.weight(.medium))
        }
    }

    // MARK: Industry Classification

    private func industry(_ form: Binding<CompanyBasicsForm>) -> some View {
        let selected = form.wrappedValue.industries.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return SetupSegment(title: "Industry Classification", hasError: session.segmentHasError([F.industries])) {
            SetupField(label: "Which industries does this company operate in?", field: F.industries) {
                VStack(alignment: .leading, spacing: 12) {
                    if !selected.isEmpty {
                        HStack {
                            Text("\(selected.count) selected")
                                .font(.footnote)
                                .foregroundStyle(AxialColor.textSecondary)
                            Spacer()
                            Button("Clear All") { isConfirmingClearIndustries = true }
                                .font(.footnote.weight(.semibold))
                        }
                        SetupChipList(items: selected.map { ($0.id, $0.name) }) { id in
                            form.wrappedValue.industries.removeAll { $0.id == id }
                            session.touch(F.industries)
                        }
                    }
                    Button {
                        isPickingIndustries = true
                    } label: {
                        Label(selected.isEmpty ? "Select Industries" : "Edit Industries", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(session.visibleError(for: F.industries) != nil ? AxialColor.error : AxialColor.brandPrimary)
                    .accessibilityIdentifier("setup-industries")
                }
            }
        }
        .fullScreenCover(isPresented: $isPickingIndustries, onDismiss: { session.touch(F.industries) }) {
            IndustryPickerSheet(selection: form.industries)
        }
        .confirmationDialog("Clear all industries?", isPresented: $isConfirmingClearIndustries, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) {
                form.wrappedValue.industries = []
                session.touch(F.industries)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all selected industries and can't be undone.")
        }
    }

    // MARK: Your Role & Mandate

    private func roleMandate(_ form: Binding<CompanyBasicsForm>, isCapitalRaise: Bool) -> some View {
        SetupSegment(title: "Your Role & Mandate",
                     hasError: session.segmentHasError([F.roleName, F.exclusiveMandate, F.expectsFeeAdvisor, F.expectsFeeInvestor])) {
            SetupRadioGroup(label: "What is your relationship to this company?", choices: CompanyBasicsOptions.roles,
                            selection: form.roleName, field: F.roleName)
            if form.wrappedValue.roleName == "advisor" {
                SetupRadioGroup(label: "Do you have an exclusive mandate?", choices: CompanyBasicsOptions.mandate,
                                selection: form.exclusiveMandate, field: F.exclusiveMandate)
                    .transition(.opacity)
                SetupRadioGroup(label: "Who will be paying your fees?",
                                choices: CompanyBasicsOptions.advisorFee(isCapitalRaise: isCapitalRaise),
                                selection: form.expectsFeeAdvisor, field: F.expectsFeeAdvisor)
                    .transition(.opacity)
            }
            if form.wrappedValue.roleName == "investor" {
                SetupRadioGroup(label: "Are you expecting a fee from the buyer?", choices: CompanyBasicsOptions.investorFee,
                                selection: form.expectsFeeInvestor, field: F.expectsFeeInvestor)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: form.wrappedValue.roleName)
    }

    // MARK: Headquarters & Location

    private func location(_ form: Binding<CompanyBasicsForm>) -> some View {
        let value = form.wrappedValue
        let hasSubdivisions = Geography.hasSubdivisions(value.country)
        let countryBinding = Binding<String?>(
            get: { value.country.isEmpty ? nil : value.country },
            set: { if let code = $0 { form.wrappedValue.setCountry(code) } }
        )
        let stateBinding = Binding<String?>(
            get: { value.state.isEmpty ? nil : value.state },
            set: { form.wrappedValue.state = $0 ?? "" }
        )
        let disclosureBinding = Binding<String?>(
            get: { value.disclosure.isEmpty ? nil : value.disclosure },
            set: { form.wrappedValue.disclosure = $0 ?? "" }
        )
        return SetupSegment(title: "Headquarters & Location",
                            hasError: session.segmentHasError([F.country, F.state, F.disclosure])) {
            SetupFieldLabel(text: "Where is the company's HQ?", isRequired: true,
                            isInvalid: session.visibleError(for: F.country) != nil || session.visibleError(for: F.state) != nil)
            SetupSearchPickerRow(label: "Country", choices: Geography.sortedCountries.map { .init(value: $0.code, label: $0.name) },
                                 selection: countryBinding, field: F.country, searchPrompt: "Search countries...")
            if hasSubdivisions {
                SetupSearchPickerRow(label: "State / Province",
                                     choices: Geography.subdivisions(forCountry: value.country).map { .init(value: $0.code, label: $0.name) },
                                     selection: stateBinding, field: F.state, searchPrompt: "Search...")
                    .transition(.opacity)
            }
            SetupRadioGroup(label: "How should this location be represented on the teaser?",
                            choices: CompanyBasicsOptions.disclosure, selection: disclosureBinding, field: F.disclosure)
                .disabled(!hasSubdivisions)
                .opacity(hasSubdivisions ? 1 : 0.5)
            SetupNotice(style: .neutral,
                        message: "Buyers love specifics! The clearer you are about the location, the more interest you'll generate.")
            if let preview = Geography.displayName(state: value.state, country: value.country, disclosure: value.disclosure) {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("This will appear as:")
                        .font(.footnote)
                        .foregroundStyle(AxialColor.textSecondary)
                    Label(preview, systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AxialColor.textPrimary)
                        .contentTransition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: hasSubdivisions)
    }

    // MARK: Company Details (Internal Use Only)

    private func internalDetails(_ form: Binding<CompanyBasicsForm>, isSellBusiness: Bool) -> some View {
        let management = Binding<String?>(
            get: { form.wrappedValue.management.isEmpty ? nil : form.wrappedValue.management },
            set: { form.wrappedValue.management = $0 ?? "" }
        )
        return SetupSegment(title: "Company Details (Internal Use Only)",
                            hasError: session.segmentHasError([F.companyName, F.companyWebsite, F.management])) {
            SetupTextField(label: "Company Name", text: form.companyName, field: F.companyName,
                           placeholder: "Enter company name")
            SetupTextField(label: "Company Website", text: form.companyWebsite, field: F.companyWebsite,
                           placeholder: "www.example.com", keyboard: .URL, contentType: .URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if isSellBusiness {
                SetupRadioGroup(label: "Does the management team expect to stay on after the deal?",
                                choices: CompanyBasicsOptions.management, selection: management, field: F.management)
            }
            SetupNotice(style: .neutral, message: "This information will not be shared with members.")
        }
    }

    // MARK: Team & Company Attributes

    private func attributes(_ form: Binding<CompanyBasicsForm>, isSellBusiness: Bool) -> some View {
        let value = form.wrappedValue
        return SetupSegment(title: "Team & Company Attributes",
                            hasError: session.segmentHasError([F.licensesRequired, F.licenseDetails, F.realEstateDetails,
                                                               F.fullTimeEmployees, F.partTimeEmployees])) {
            if isSellBusiness {
                SetupRadioGroup(label: "Are any licenses required to operate the business?",
                                choices: CompanyBasicsOptions.yesNo, selection: form.licensesRequired, field: F.licensesRequired)
                if value.licensesRequired == "yes" {
                    SetupTextEditor(label: "Describe those licenses required", text: form.licenseDetails,
                                    field: F.licenseDetails, placeholder: "Enter license details", minHeight: 80)
                        .transition(.opacity)
                }
            }
            SetupRadioGroup(label: "Real Estate Included?", choices: CompanyBasicsOptions.yesNo,
                            selection: form.realEstateIncluded, field: F.realEstateIncluded)
            if value.realEstateIncluded == "yes" {
                SetupTextEditor(label: "Describe the real estate", text: form.realEstateDetails,
                                field: F.realEstateDetails, placeholder: "Enter real estate details", minHeight: 80)
                    .transition(.opacity)
            }
            HStack(alignment: .top, spacing: 12) {
                SetupNumberField(label: "Full-Time Employees", value: form.fullTimeEmployees, field: F.fullTimeEmployees,
                                 placeholder: "e.g. 50", prefix: nil, allowsNegative: true)
                SetupNumberField(label: "Part-Time Employees", value: form.partTimeEmployees, field: F.partTimeEmployees,
                                 placeholder: "e.g. 10", prefix: nil, allowsNegative: true)
            }
            SetupMenuPicker(label: "Business Established Year",
                            choices: CompanyBasicsOptions.years(now: session.context.now),
                            selection: form.yearEstablished, field: F.yearEstablished, placeholder: "Select year",
                            allowsClear: true)
            if isSellBusiness {
                SetupMenuPicker(label: "Reason for Sale", choices: CompanyBasicsOptions.reasonsForSale,
                                selection: form.reasonForSale, field: F.reasonForSale, placeholder: "Select reason",
                                allowsClear: true)
            }
            SetupCheckboxGroup(label: "Business Attributes", choices: CompanyBasicsOptions.businessAttributes,
                               selection: Binding(
                                   get: { Set(form.wrappedValue.businessAttributes) },
                                   set: { new in
                                       // Keep the order things were picked in.
                                       var ordered = form.wrappedValue.businessAttributes.filter(new.contains)
                                       ordered += CompanyBasicsOptions.businessAttributes.map(\.value)
                                           .filter { new.contains($0) && !ordered.contains($0) }
                                       form.wrappedValue.businessAttributes = ordered
                                   }),
                               field: F.businessAttributes)
        }
        .animation(.easeOut(duration: 0.2), value: value.licensesRequired)
        .animation(.easeOut(duration: 0.2), value: value.realEstateIncluded)
    }

    // MARK: End Markets

    private func endMarkets(_ form: Binding<CompanyBasicsForm>) -> some View {
        SetupSegment(title: "End Markets", hasError: session.segmentHasError([F.customerTypes])) {
            SetupPickerRow(label: "Which end markets does this company sell into?", field: F.customerTypes,
                           summary: EndMarkets.summary(form.wrappedValue.customerTypes),
                           placeholder: "Select End Markets") {
                isPickingEndMarkets = true
            }
        }
        .sheet(isPresented: $isPickingEndMarkets, onDismiss: { session.touch(F.customerTypes) }) {
            EndMarketsSheet(selection: form.customerTypes)
        }
    }
}

/// `axl-tree-select-new` for End Markets: the three roots, Enterprise with
/// a tri-state "select all".
struct EndMarketsSheet: View {
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(EndMarkets.tree) { node in
                    if node.children.isEmpty {
                        row(node.label, state: selection.contains(node.key) ? .on : .off) {
                            toggle([node.key])
                        }
                    } else {
                        Section {
                            let keys = node.children.map(\.key)
                            let count = keys.filter(selection.contains).count
                            row(node.label, state: count == keys.count ? .on : count > 0 ? .mixed : .off, isBold: true) {
                                if count == keys.count { selection.subtract(keys) } else { selection.formUnion(keys) }
                            }
                            ForEach(node.children) { child in
                                row(child.label, state: selection.contains(child.key) ? .on : .off) {
                                    toggle([child.key])
                                }
                                .padding(.leading, 24)
                            }
                        }
                    }
                }
            }
            .navigationTitle("End Markets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { selection = [] }.disabled(selection.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private enum CheckState { case on, off, mixed }

    private func toggle(_ keys: [String]) {
        Haptics.selection()
        for key in keys {
            if selection.contains(key) { selection.remove(key) } else { selection.insert(key) }
        }
    }

    private func row(_ label: String, state: CheckState, isBold: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: state == .on ? "checkmark.square.fill" : state == .mixed ? "minus.square.fill" : "square")
                    .foregroundStyle(state == .off ? AxialColor.textPlaceholder : AxialColor.brandPrimary)
                Text(label)
                    .fontWeight(isBold ? .semibold : .regular)
                    .foregroundStyle(AxialColor.textPrimary)
            }
        }
    }
}
