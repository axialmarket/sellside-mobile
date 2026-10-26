//
//  ProjectSetupFormTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Axial_Mobile

/// Web sources cited per test: project-setup.steps.ts, the step-definition.ts
/// files, company-basics.form.ts, financials-step, documents steps,
/// sharing-settings.service.ts, project-setup-sidenav.component.ts.
struct ProjectSetupFormTests {

    private static let now: Date = {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 5; parts.day = 14; parts.hour = 12
        return Calendar.current.date(from: parts)!
    }()

    private static func context(_ type: String = "sell_business", intentState: String = "draft") -> SetupContext {
        SetupContext(intentType: type, supplyState: "draft", intentState: intentState, now: now)
    }

    // MARK: - Structure

    @Test func capitalRaiseOnlyAppearsForRaiseCapital() {
        #expect(!Self.context().sequence.contains(.capitalRaise))
        #expect(Self.context("raise_capital").sequence.prefix(3) == [.companyBasics, .capitalRaise, .financials])
    }

    @Test func theDealLinkStepNeedsAnActiveProject() {
        #expect(!Self.context().sequence.contains(.advancedSharing))
        #expect(Self.context(intentState: "active").sequence.last == .advancedSharing)
    }

    @Test func nextAndPreviousCrossSections() {
        let context = Self.context()
        #expect(context.next(after: .financials) == .customTeaser)
        #expect(context.previous(before: .customTeaser) == .financials)
        #expect(context.next(after: .messaging) == nil)
    }

    @Test func progressTextMatchesTheSidenav() {
        // `computeText`.
        #expect(StepProgress(required: 0, completed: 0).text == "Optional")
        #expect(StepProgress(required: 5, completed: 2).text == "2 of 5")
        #expect(StepProgress(required: 2, completed: 2).text == "All required steps complete!")
    }

    @Test func theErrorIconWaitsForReview() {
        let incomplete = StepProgress(required: 3, completed: 1)
        #expect(incomplete.indicator(showingErrors: false) == .inProgress)
        #expect(incomplete.indicator(showingErrors: true) == .error)
    }

    @Test func completionCopyPluralises() {
        #expect(SetupCompletion(incompleteSteps: [.nda]).text == "1 Required Step Incomplete")
        #expect(SetupCompletion(incompleteSteps: [.nda, .financials]).text == "2 Required Steps Incomplete")
        #expect(SetupCompletion(incompleteSteps: []).text == "All required steps complete!")
    }

    // MARK: - Company Basics

    private static func basicsProgress(_ form: CompanyBasicsForm, _ context: SetupContext = context()) -> StepProgress {
        var builder = StepValidationBuilder(step: .companyBasics)
        form.validate(context: context, into: &builder)
        return builder.progress
    }

    @Test func aSellBusinessAdvisorInTheUSHasThirteenRequiredFields() {
        // §1.10: the post-render count.
        var form = CompanyBasicsForm(intent: [:])
        form.roleName = "advisor"
        #expect(Self.basicsProgress(form).required == 13)
        form.licensesRequired = "yes"
        form.realEstateIncluded = "yes"
        #expect(Self.basicsProgress(form).required == 15)
    }

    @Test func raiseCapitalDropsManagementAndLicenses() {
        var form = CompanyBasicsForm(intent: [:])
        form.roleName = "advisor"
        #expect(Self.basicsProgress(form, Self.context("raise_capital")).required == 11)
    }

    @Test func outsideNorthAmericaTheStateIsNotRequired() {
        var form = CompanyBasicsForm(intent: [:])
        form.roleName = "ceo"
        form.setCountry("GB")
        #expect(form.disclosure == "country")
        #expect(form.state.isEmpty)
        #expect(Self.basicsProgress(form).required == 9)
    }

    @Test func theHeadlineCountsTowardTenCharacters() {
        var form = CompanyBasicsForm(intent: [:])
        form.headline = "Too short"
        var builder = StepValidationBuilder(step: .companyBasics)
        form.validate(context: Self.context(), into: &builder)
        #expect(builder.errors[CompanyBasicsForm.Field.headline] == "9 of 10 character minimum.")
        form.headline = String(repeating: "x", count: 141)
        builder = StepValidationBuilder(step: .companyBasics)
        form.validate(context: Self.context(), into: &builder)
        #expect(builder.errors[CompanyBasicsForm.Field.headline] == "Maximum 140 characters allowed.")
    }

    @Test func endMarketsSaveAsLeafKeys() {
        // A saved parent key expands to its fifteen leaves.
        let form = CompanyBasicsForm(intent: ["customer_types": ["consumer", "enterprise"]])
        var intent: JSONValue = [:]
        form.write(into: &intent, context: Self.context())
        let saved = intent["customer_types"]?.strings ?? []
        #expect(saved.count == 16)
        #expect(!saved.contains("enterprise"))
        #expect(EndMarkets.summary(form.customerTypes) == ["Consumer", "Enterprise"])
    }

    @Test func headquartersRoundTripsThroughGeographyIDs() {
        let form = CompanyBasicsForm(intent: ["company": ["geographies": [32]]])
        #expect(form.country == "US")
        #expect(form.state == "CA")
        #expect(Geography.geographies(state: form.state, country: form.country) == [32])
        #expect(Geography.displayName(state: "CA", country: "US", disclosure: "region") == "US - Pacific (CA, OR, WA, HI, AK)")
        #expect(Geography.displayName(state: "", country: "GB", disclosure: "country") == "Northern Europe")
    }

    @Test func untouchedDescriptionHTMLWritesBackUnchanged() {
        var value = RichTextValue(html: "<p>One <strong>bold</strong> line.</p>")
        #expect(value.text == "One bold line.")
        #expect(value.html == "<p>One <strong>bold</strong> line.</p>")
        value.text = "One line.\n\nTwo."
        #expect(value.html == "<p>One line.</p><p>Two.</p>")
    }

    // MARK: - Capital Raise

    @Test func debtTypesCapAtFiveAndOpenToAnyIsExclusive() {
        var leaves: Set<String> = []
        for key in ["factoring", "inventory", "term_loan", "revolver", "venture", "mezzanine"] {
            leaves = DebtTypes.toggle(key, in: leaves)
        }
        #expect(leaves.count == 5)
        #expect(!leaves.contains("mezzanine"))
        #expect(DebtTypes.toggle(DebtTypes.openToAny, in: leaves) == [DebtTypes.openToAny])
    }

    @Test func aFullyCheckedParentSavesAsItsKey() {
        let leaves: Set<String> = ["accounts_receivable", "factoring", "inventory", "equipment"]
        #expect(DebtTypes.value(from: leaves) == ["abl"])
        #expect(DebtTypes.checkedLeaves(["abl"]) == leaves)
    }

    @Test func minimumAboveTotalFlagsBoth() {
        var form = CapitalRaiseForm(intent: [:])
        form.capitalType = "equity"
        form.useOfFunds = ["growth"]
        form.maxRange = 1
        form.minRange = 2
        var builder = StepValidationBuilder(step: .capitalRaise)
        form.validate(into: &builder)
        #expect(builder.errors[CapitalRaiseForm.Field.maxRange] == "Total amount should be more than minimum check size.")
        #expect(builder.errors[CapitalRaiseForm.Field.minRange] == "Minimum check size should be less than total amount.")
        #expect(builder.progress.completed == 2)
    }

    // MARK: - Financials

    @Test func financialsCompleteWithRevenueAndEbitdaInTheLTMOrRecentYear() {
        // FY December, May 2026 → 2025 is the most recent completed year.
        #expect(FiscalCalendar.mostRecentCompletedYear(now: Self.now, fyEndMonth: 12) == 2025)
        #expect(FiscalCalendar.mostRecentCompletedYear(now: Self.now, fyEndMonth: 3) == 2026)
        let rows = [FinancialRow(financialType: "revenue", timePeriod: "2025", value: 10),
                    FinancialRow(financialType: "ebitda", timePeriod: "2025", value: 0)]
        #expect(PeriodicFinancials(rows: rows).isComplete(now: Self.now, fyEndMonth: 12))
        #expect(!PeriodicFinancials(rows: rows).isComplete(now: Self.now, fyEndMonth: 3))
    }

    @Test func ebitdaAtOrAboveRevenueIsAConflict() {
        let rows = [FinancialRow(financialType: "revenue", timePeriod: "ltm", value: 5),
                    FinancialRow(financialType: "ebitda", timePeriod: "ltm", value: 5)]
        #expect(PeriodicFinancials(rows: rows).hasMinMaxConflict)
    }

    @Test func cellsAreTypedInMillions() {
        #expect(FinancialCellRules.sanitize("$2,500,000", unit: "$") == "2.5")
        #expect(FinancialCellRules.sanitize("1-2", unit: "$") == "12")
        #expect(FinancialCellRules.display(2) == "2.0")
        #expect(FinancialCellRules.validateStandard("0", metric: "revenue") == .invalidValue)
        #expect(FinancialCellRules.validateStandard("0", metric: "ebitda") == nil)
        #expect(FinancialCellRules.validateStandard("1000", metric: "revenue") == .outOfRange)
        #expect(FinancialCellRules.summary(25_000_000, unit: "$") == "$25.0M")
    }

    @Test func theTableOpensWithFiveColumnsAndLTMAfterTheLastActual() {
        let table = FinancialTable(rows: [], fiscalYearEnd: 12, now: Self.now, catalog: .empty)
        #expect(table.columns == [.year(2023), .year(2024), .year(2025), .ltm, .year(2026)])
        #expect(table.isLocked(.ltm) && table.isLocked(.year(2025)))
        #expect(table.isProjected(.year(2026)))
        #expect(table.label(.year(2025)) == "Dec 2025")
    }

    @Test func aColumnWithEbitdaAboveRevenueExplainsItself() {
        var table = FinancialTable(rows: [], fiscalYearEnd: 12, now: Self.now, catalog: .empty)
        table.setRaw("5", metric: "revenue", column: .ltm)
        table.commit(metric: "revenue", column: .ltm, catalog: .empty)
        table.setRaw("6", metric: "ebitda", column: .ltm)
        table.commit(metric: "ebitda", column: .ltm, catalog: .empty)
        #expect(table.hasConflict)
        #expect(table.conflictMessages(catalog: .empty) == ["EBITDA must be less than Revenue"])
        table.clearInvalidCells(catalog: .empty)
        #expect(!table.hasConflict)
    }

    @Test func tablePayloadStoresDollarsAndMarksProjections() {
        var table = FinancialTable(rows: [], fiscalYearEnd: 12, now: Self.now, catalog: .empty)
        table.setRaw("2.5", metric: "revenue", column: .year(2026))
        #expect(table.rows == [FinancialRow(financialType: "revenue", timePeriod: "2026", isEstimated: true, value: 2_500_000)])
    }

    @Test func aKPIReachesThePayloadOnlyOnceBlurredAndValid() {
        let catalog = FinancialCatalog(types: [FinancialType(key: "customer_count", label: "Customer Count", uom: "qty",
                                                             canBeNonPeriodic: true, minAllowed: 0, isWholeNumber: true)],
                                       exclusions: [])
        var form = FinancialsForm(intent: [:], now: Self.now)
        let id = form.kpis[0].id
        form.setKPIMetric(id, to: "customer_count", catalog: catalog)
        form.kpis[0].raw = "140"
        #expect(form.committedKPIs.isEmpty)
        form.commitKPI(id, catalog: catalog)
        #expect(form.committedKPIs.map(\.value) == [140])
        // Whole-number metrics round on blur, so "1.5" would pass as 2;
        // below the minimum doesn't.
        form.kpis[0].raw = "-3"
        form.commitKPI(id, catalog: catalog)
        #expect(form.kpis[0].error == .invalidValue)
        #expect(form.committedKPIs.isEmpty)
    }

    @Test func valuationKeepsTheLastValidRangeUntilCleared() {
        var valuation = ValuationInput()
        valuation.metric = "ebitda_multiple"
        valuation.max = 7.5
        valuation.commitIfValid()
        #expect(valuation.committed?.maxValue == 7.5)
        #expect(valuation.committed?.minValue == 0)
        valuation.min = 9
        valuation.commitIfValid()
        #expect(valuation.committed?.maxValue == 7.5)
        valuation.clear()
        #expect(valuation.committed == nil)
    }

    // MARK: - Documents

    @Test func aLinkedNDAIsCustomWithAURL() {
        let documents = SetupDocuments(intent: [:])
        var nda = NDAForm(intent: ["nda_type": "linked", "linked_nda": "https://x.com/nda.pdf"], documents: documents)
        #expect(nda.ndaType == "custom")
        var intent: JSONValue = [:]
        nda.write(into: &intent)
        #expect(intent["nda_type"] == "linked")
        nda.linkedNdaUrl = ""
        var builder = StepValidationBuilder(step: .nda)
        nda.validate(documents: documents, into: &builder)
        #expect(builder.progress.completed == 0)
    }

    @Test func automaticCIMShareNeedsASignableNDA() {
        // `cimValidator`.
        var documents = SetupDocuments(intent: [:])
        documents.add(bucket: "OM", filename: "cim.pdf", mimeType: "application/pdf", data: Data())
        var cim = CIMForm(intent: [:], documents: documents)
        cim.cimType = "custom"
        cim.smartshareState = "enabled"
        var nda = NDAForm(intent: [:], documents: documents)
        nda.ndaType = "waive"
        #expect(cim.groupIssue(nda: nda, documents: documents) == .requiresSignableNDA)
        nda.ndaType = "axial"
        #expect(cim.groupIssue(nda: nda, documents: documents) == nil)
        cim.smartshareState = nil
        #expect(cim.groupIssue(nda: nda, documents: documents) == .requiresSharingMethod)
    }

    @Test func removingAnUnsavedFileLeavesNothingToDelete() {
        var documents = SetupDocuments(intent: ["documents": [["id": "d1", "type": "OM", "filename": "old.pdf"]]])
        documents.add(bucket: "OM", filename: "new.pdf", mimeType: "application/pdf", data: Data())
        let added = documents.cimDocuments[1]
        documents.remove(added)
        #expect(documents.pendingUploads.isEmpty && documents.pendingDeletions.isEmpty)
        documents.remove(documents.cimDocuments[0])
        #expect(documents.pendingDeletions.map(\.serverID) == ["d1"])
    }

    @Test func urlsFollowTheWebValidator() {
        #expect(URLRule.isValid(""))
        #expect(URLRule.isValid("www.example.com"))
        #expect(URLRule.isValid("https://cal.com/me/30min"))
        #expect(!URLRule.isValid("not a url"))
        #expect(URLRule.sanitized("example.com") == "https://example.com")
    }

    // MARK: - Sharing

    @Test func inboundInquiryLoadsAsManualWithApproval() {
        let form = SharingSettingsForm(intent: ["use_smartshare": true, "requires_approval": true,
                                                "owned_by_account": ["can_manually_share": true]])
        #expect(form.sharingMode == "manual")
        #expect(form.requiresApproval)
        var intent: JSONValue = [:]
        form.write(into: &intent)
        #expect(intent["use_smartshare"] == true)
        #expect(intent["requires_approval"] == true)
    }

    @Test func pickingSmartShareTurnsInboundInquiryOff() {
        var form = SharingSettingsForm(intent: ["use_smartshare": false, "requires_approval": false])
        form.setSharingMode("smartshare")
        #expect(!form.requiresApproval)
        form.setSharingMode("manual")
        #expect(form.requiresApproval)
    }

    @Test func allCompanyTypesSavesAsNoFilter() {
        var form = SharingSettingsForm(intent: [:])
        form.companyTypes = OutreachOptions.companyTypes.map(\.value)
        #expect(form.preferenceLabels == ["Company Type: All Company Types"])
        #expect(form.advancedFilters["account_type"] == .array([]))
    }

    @Test func suppressionRejectsFreeEmailDomains() {
        #expect(Counterparty.validationError(for: "@bigco.com") == nil)
        #expect(Counterparty.validationError(for: "jane@gmail.com") == nil)
        #expect(Counterparty.validationError(for: "gmail.com")
            == "Public email domains (like Gmail, Yahoo) cannot be suppressed. Please enter a private business domain.")
        #expect(Counterparty.validationError(for: "not valid")
            == "Enter a valid email address, email domain (e.g. @axial.com), or website")
        #expect(Counterparty.entries(from: "a.com, b.com\nc.com") == ["a.com", "b.com", "c.com"])
    }

    @Test func locationsRollUpToRegionsAndCountries() {
        let pacific = Set([28, 32, 39, 65, 75])
        #expect(Geography.rolledUp(pacific) == [10])
        let allUS = Set(Geography.localTiers[0].leafIDs)
        #expect(Geography.rolledUp(allUS) == [1])
        #expect(Geography.leaves(for: [10]) == pacific)
    }

    // MARK: - Review

    @Test func inboundInquiryOnIsOneChangeNamedInboundInquiry() {
        let baseline: JSONValue = ["use_smartshare": false, "requires_approval": false]
        let current: JSONValue = ["use_smartshare": true, "requires_approval": true]
        let changes = ReviewChanges.changes(from: baseline, to: current, documents: SetupDocuments(intent: [:]),
                                            canManuallyShare: true)
        #expect(changes.map(\.name) == ["Inbound Inquiry"])
    }

    @Test func changesAreNamedAndSortedLikeTheWeb() {
        let baseline: JSONValue = ["headline": "a", "company": ["industries": [], "financials": []], "teaser": ["message": "x"]]
        let current: JSONValue = ["headline": "b", "company": ["industries": [1], "financials": [1]], "teaser": ["message": "y"]]
        let changes = ReviewChanges.changes(from: baseline, to: current, documents: SetupDocuments(intent: [:]),
                                            canManuallyShare: true)
        #expect(changes.map(\.name) == ["External Headline", "Industries", "Historical Metrics", "Teaser Message"])
        #expect(changes.map(\.step) == [.companyBasics, .companyBasics, .financials, .messaging])
    }
}
