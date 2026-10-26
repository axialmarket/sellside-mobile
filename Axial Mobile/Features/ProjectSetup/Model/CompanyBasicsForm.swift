//
//  CompanyBasicsForm.swift
//  Axial Mobile
//

import Foundation

/// One selected industry — `IndustrySelection` (industry-selection.model.ts).
/// Identity is `vertical:activity:industry`, since one industry can sit in
/// several vertical/activity groups.
struct IndustrySelection: Hashable, Identifiable {
    let vertical: Int
    let activity: Int
    let industryID: Int?
    let name: String

    var id: String { "\(vertical):\(activity):\(industryID.map(String.init) ?? "")" }

    init(vertical: Int, activity: Int, industryID: Int?, name: String) {
        self.vertical = vertical
        self.activity = activity
        self.industryID = industryID
        self.name = name
    }

    init?(json: JSONValue) {
        guard let vertical = json["vertical"]?.int, let activity = json["activity"]?.int else { return nil }
        self.init(vertical: vertical, activity: activity,
                  industryID: json["industry"]?["id"]?.int,
                  name: json["industry"]?["name"]?.string ?? "")
    }

    /// `toData()`.
    var json: JSONValue {
        var object: [String: JSONValue] = ["vertical": .number(Double(vertical)), "activity": .number(Double(activity))]
        if let industryID {
            object["industry"] = ["id": .number(Double(industryID)), "name": .string(name)]
        }
        return .object(object)
    }
}

/// The Company Basics step — company-basics.form.ts and
/// `applyCompanyBasicsToIntentShell` (step-definition.ts).
struct CompanyBasicsForm: Equatable {
    // Project & Company Details
    var internalName: String
    var headline: String
    var description: RichTextValue
    // Industry Classification
    var industries: [IndustrySelection]
    /// No UI here; carried through so a save doesn't drop it.
    var industriesNegative: JSONValue
    // Your Role & Mandate
    var roleName: String?
    var exclusiveMandate: String?
    var expectsFeeAdvisor: String?
    var expectsFeeInvestor: String?
    // Headquarters & Location
    var country: String
    var state: String
    var disclosure: String
    // Company Details (Internal Use Only)
    var companyName: String
    var companyWebsite: String
    var management: String
    // Team & Company Attributes
    var licensesRequired: String?
    var licenseDetails: String
    var realEstateIncluded: String?
    var realEstateDetails: String
    var fullTimeEmployees: Double?
    var partTimeEmployees: Double?
    var yearEstablished: String?
    var reasonForSale: String?
    var businessAttributes: [String]
    // End Markets — leaf keys.
    var customerTypes: Set<String>

    static let internalNameMax = 70
    static let headlineMin = 10
    static let headlineMax = 140
    static let descriptionMin = 300

    init(intent: JSONValue) {
        internalName = intent["internal_name"]?.string ?? ""
        headline = intent["headline"]?.string ?? ""
        description = RichTextValue(html: intent["description"]?.string ?? "")
        let company = intent["company"]
        industries = company?["industries"]?["positive"]?.array?.compactMap(IndustrySelection.init(json:)) ?? []
        industriesNegative = company?["industries"]?["negative"] ?? .array([])

        roleName = intent["role_types"]?.strings.first
        exclusiveMandate = intent[path: "roles.advisor.exclusive_mandate"]?.text
        expectsFeeAdvisor = intent[path: "roles.advisor.expects_buyer_fee"]?.text
        expectsFeeInvestor = intent[path: "roles.investor.expects_buyer_fee"]?.text

        let location = Geography.location(fromGeographyID: company?["geographies"]?.array?.first?.int)
        country = location.country
        state = location.state
        disclosure = intent["geography_disclosure"]?.text ?? "region"

        companyName = company?["company_name"]?.string ?? ""
        companyWebsite = intent["company_website"]?.string ?? ""
        management = intent[path: "terms.ma.ceo_exiting_type"]?.text ?? "open"

        licensesRequired = Self.yesNo(company?["licenses_required"])
        licenseDetails = company?["license_details"]?.string ?? ""
        realEstateIncluded = Self.yesNo(company?["real_estate_included"])
        realEstateDetails = company?["real_estate_details"]?.string ?? ""
        fullTimeEmployees = company?["full_time_employee_count"]?.number
        partTimeEmployees = company?["part_time_employee_count"]?.number
        yearEstablished = company?["year_established"]?.int.map(String.init)
        reasonForSale = company?["reason_for_sale"]?.text
        businessAttributes = company?["business_attributes"]?.strings ?? []
        customerTypes = Set(EndMarkets.leafKeys(in: intent["customer_types"]?.strings ?? []))
    }

    private static func yesNo(_ value: JSONValue?) -> String? {
        switch value?.bool {
        case true?: "yes"
        case false?: "no"
        default: nil
        }
    }

    private static func bool(_ yesNo: String?) -> JSONValue {
        switch yesNo {
        case "yes": true
        case "no": false
        default: .null
        }
    }

    // MARK: Payload

    func write(into intent: inout JSONValue, context: SetupContext) {
        intent.set(.string(internalName), at: "internal_name")
        intent.set(.string(orNull: companyWebsite.isEmpty ? nil : companyWebsite), at: "company_website")
        intent.set(.string(description.html), at: "description")
        intent.set(.string(RichText.stripTags(headline)), at: "headline")
        intent.set(["positive": .array(industries.map(\.json)), "negative": industriesNegative], at: "company.industries")
        intent.set(.array(Geography.geographies(state: state, country: country).map { .number(Double($0)) }),
                   at: "company.geographies")
        if !disclosure.isEmpty {
            intent.set(.string(disclosure), at: "geography_disclosure")
        } else if var object = intent.object {
            // The API rejects an empty enum, so the key goes instead.
            object["geography_disclosure"] = nil
            intent = .object(object)
        }
        if intent[path: "terms.ma"]?.object != nil {
            if !context.isCapitalRaise, !management.isEmpty {
                intent.set(.string(management), at: "terms.ma.ceo_exiting_type")
            } else if var ma = intent[path: "terms.ma"]?.object {
                ma["ceo_exiting_type"] = nil
                intent.set(.object(ma), at: "terms.ma")
            }
        }
        intent.set(.strings(EndMarkets.leafKeys(in: Array(customerTypes))), at: "customer_types")
        if let roleName {
            intent.set(.strings([roleName]), at: "role_types")
            // Only the current role's branch is written; the other role's
            // answers stay as they were. Web quirk, mirrored.
            switch roleName {
            case "investor":
                intent.set(.string(orNull: expectsFeeInvestor), at: "roles.investor.expects_buyer_fee")
            case "advisor":
                intent.set(.string(orNull: expectsFeeAdvisor), at: "roles.advisor.expects_buyer_fee")
                intent.set(.string(orNull: exclusiveMandate), at: "roles.advisor.exclusive_mandate")
            default: break
            }
        }
        intent.set(.number(orNull: yearEstablished.flatMap(Double.init)), at: "company.year_established")
        intent.set(.string(orNull: companyName.isEmpty ? nil : companyName), at: "company.company_name")
        intent.set(.number(orNull: fullTimeEmployees), at: "company.full_time_employee_count")
        intent.set(.number(orNull: partTimeEmployees), at: "company.part_time_employee_count")
        intent.set(.strings(businessAttributes), at: "company.business_attributes")
        intent.set(Self.bool(realEstateIncluded), at: "company.real_estate_included")
        intent.set(.string(orNull: realEstateIncluded == "yes" ? realEstateDetails : nil), at: "company.real_estate_details")
        if context.intentType == "sell_business" {
            intent.set(.string(orNull: reasonForSale), at: "company.reason_for_sale")
            intent.set(Self.bool(licensesRequired), at: "company.licenses_required")
            intent.set(.string(orNull: licensesRequired == "yes" ? licenseDetails : nil), at: "company.license_details")
        }
    }

    // MARK: Validation

    enum Field {
        static let internalName: SetupFieldKey = "companyBasics.internal_name"
        static let headline: SetupFieldKey = "companyBasics.headline"
        static let description: SetupFieldKey = "companyBasics.description"
        static let industries: SetupFieldKey = "companyBasics.industries"
        static let roleName: SetupFieldKey = "companyBasics.roleName"
        static let exclusiveMandate: SetupFieldKey = "companyBasics.exclusive-mandate"
        static let expectsFeeAdvisor: SetupFieldKey = "companyBasics.expecting-fee-advisor"
        static let expectsFeeInvestor: SetupFieldKey = "companyBasics.expecting-fee-investor"
        static let country: SetupFieldKey = "companyBasics.location.country"
        static let state: SetupFieldKey = "companyBasics.location.state-province"
        static let disclosure: SetupFieldKey = "companyBasics.geography-disclosure"
        static let companyName: SetupFieldKey = "companyBasics.company_name"
        static let companyWebsite: SetupFieldKey = "companyBasics.company_website"
        static let management: SetupFieldKey = "companyBasics.management"
        static let licensesRequired: SetupFieldKey = "companyBasics.licenses_required"
        static let licenseDetails: SetupFieldKey = "companyBasics.license_details"
        static let realEstateIncluded: SetupFieldKey = "companyBasics.real_estate_included"
        static let realEstateDetails: SetupFieldKey = "companyBasics.real_estate_details"
        static let fullTimeEmployees: SetupFieldKey = "companyBasics.full_time_employees"
        static let partTimeEmployees: SetupFieldKey = "companyBasics.part_time_employees"
        static let yearEstablished: SetupFieldKey = "companyBasics.year_established"
        static let reasonForSale: SetupFieldKey = "companyBasics.reason_for_sale"
        static let businessAttributes: SetupFieldKey = "companyBasics.business_attributes"
        static let customerTypes: SetupFieldKey = "companyBasics.customer-types"
    }

    var headlineCountText: String { "\(headline.count) of \(Self.headlineMin) character minimum." }
    var descriptionCountText: String { "\(description.visibleLength) of \(Self.descriptionMin) character minimum." }

    /// Counted in the web's declaration order. Most required fields carry no
    /// message on the web — just the red asterisk and border — and that's
    /// kept: an empty message draws the invalid state without a sentence.
    func validate(context: SetupContext, into v: inout StepValidationBuilder) {
        let nameTooLong = internalName.count > Self.internalNameMax
        v.require(Field.internalName, satisfied: !internalName.isEmpty && !nameTooLong,
                  error: nameTooLong ? "Maximum \(Self.internalNameMax) characters allowed." : "")

        let headlineTooLong = headline.count > Self.headlineMax
        v.require(Field.headline,
                  satisfied: headline.count >= Self.headlineMin && !headlineTooLong,
                  error: headlineTooLong ? "Maximum \(Self.headlineMax) characters allowed." : headlineCountText)

        v.require(Field.description, satisfied: description.visibleLength >= Self.descriptionMin,
                  error: descriptionCountText)
        v.require(Field.industries, satisfied: !industries.isEmpty, error: "")

        v.require(Field.roleName, satisfied: roleName != nil, error: "")
        switch roleName {
        case "advisor":
            v.require(Field.exclusiveMandate, satisfied: exclusiveMandate != nil, error: "")
            v.require(Field.expectsFeeAdvisor, satisfied: expectsFeeAdvisor != nil, error: "")
        case "investor":
            v.require(Field.expectsFeeInvestor, satisfied: expectsFeeInvestor != nil, error: "")
        default: break
        }

        v.require(Field.country, satisfied: !country.isEmpty, error: "")
        // Counted from the start here; on the web it only counts once the
        // location segment has rendered — so mobile's M is the post-render M.
        if Geography.hasSubdivisions(country) {
            v.require(Field.state, satisfied: !state.isEmpty, error: "")
            v.require(Field.disclosure, satisfied: !disclosure.isEmpty, error: "")
        }

        // An invalid website has no message on the web either — just red.
        v.check(Field.companyWebsite, error: URLRule.isValid(companyWebsite) ? nil : "")
        if !context.isCapitalRaise {
            v.require(Field.management, satisfied: !management.isEmpty, error: "")
        }
        if context.intentType == "sell_business" {
            v.require(Field.licensesRequired, satisfied: licensesRequired != nil, error: "")
            if licensesRequired == "yes" {
                v.require(Field.licenseDetails,
                          satisfied: !licenseDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, error: "")
            }
        }
        if realEstateIncluded == "yes" {
            v.require(Field.realEstateDetails,
                      satisfied: !realEstateDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, error: "")
        }
        v.check(Field.fullTimeEmployees, error: (fullTimeEmployees ?? 0) < 0 ? "" : nil)
        v.check(Field.partTimeEmployees, error: (partTimeEmployees ?? 0) < 0 ? "" : nil)
        v.require(Field.customerTypes, satisfied: !customerTypes.isEmpty, error: "")
    }

    /// Fields whose web errors show before the field is touched — the
    /// max-length messages render whenever the error exists.
    var immediateErrors: Set<SetupFieldKey> {
        var fields: Set<SetupFieldKey> = []
        if internalName.count > Self.internalNameMax { fields.insert(Field.internalName) }
        if headline.count > Self.headlineMax { fields.insert(Field.headline) }
        return fields
    }

    // MARK: Behaviour

    /// Changing country clears the state; outside the US and Canada the
    /// teaser can only show the country.
    mutating func setCountry(_ code: String) {
        guard code != country else { return }
        country = code
        state = ""
        if !Geography.hasSubdivisions(code), disclosure != "country" { disclosure = "country" }
    }
}

// MARK: - Options

enum CompanyBasicsOptions {
    static let roles: [SetupChoice<String>] = [
        .init(value: "advisor", label: "Advisor"),
        .init(value: "ceo", label: "CEO / CFO"),
        .init(value: "investor", label: "Investor / Board Member"),
    ]

    static let mandate: [SetupChoice<String>] = [
        .init(value: "yes", label: "Yes"),
        .init(value: "no", label: "No"),
    ]

    static func advisorFee(isCapitalRaise: Bool) -> [SetupChoice<String>] {
        [.init(value: "no", label: isCapitalRaise ? "Capital Raiser" : "Seller"),
         .init(value: "yes", label: isCapitalRaise ? "Capital Provider" : "Buyer")]
    }

    static let investorFee: [SetupChoice<String>] = [
        .init(value: "no", label: "No"),
        .init(value: "yes", label: "Yes"),
    ]

    static let disclosure: [SetupChoice<String>] = [
        .init(value: "country", label: "Only display the country / global region"),
        .init(value: "region", label: "Display the region (for US and Canada only)"),
        .init(value: "state", label: "Display the specific state / province (for US and Canada only)"),
    ]

    static let management: [SetupChoice<String>] = [
        .init(value: "yes", label: "Management will stay"),
        .init(value: "no", label: "Management will exit"),
        .init(value: "open", label: "It's flexible"),
    ]

    static let yesNo: [SetupChoice<String>] = [
        .init(value: "yes", label: "Yes"),
        .init(value: "no", label: "No"),
    ]

    static func years(now: Date, calendar: Calendar = .current) -> [SetupChoice<String>] {
        let current = calendar.component(.year, from: now)
        return stride(from: current, through: 1900, by: -1).map { .init(value: String($0), label: String($0)) }
    }

    static let reasonsForSale: [SetupChoice<String>] = [
        .init(value: "retirement_succession_planning", label: "Retirement / Succession planning"),
        .init(value: "pursuing_new_opportunities", label: "Pursuing new opportunities"),
        .init(value: "partnership_dissolution", label: "Partnership dissolution"),
        .init(value: "financial_need", label: "Financial need"),
        .init(value: "business_relocation", label: "Business relocation"),
        .init(value: "health_reasons", label: "Health reasons"),
        .init(value: "market_conditions_strategic_exit", label: "Market conditions / strategic exit"),
        .init(value: "other", label: "Other"),
    ]

    static let businessAttributes: [SetupChoice<String>] = [
        .init(value: "franchise", label: "Franchise"),
        .init(value: "women_owned_business", label: "Women-owned business"),
        .init(value: "minority_owned_business", label: "Minority-owned business"),
        .init(value: "veteran_owned_business", label: "Veteran-owned business"),
        .init(value: "remote_relocatable_business", label: "Remote / Relocatable business"),
        .init(value: "government_contracts", label: "Government contracts"),
        .init(value: "unionized_workforce", label: "Unionized workforce"),
    ]
}

/// collapsible-checkboxes.constants.ts — three roots, Enterprise with 15
/// children. Saved as leaf keys only.
enum EndMarkets {
    struct Node: Identifiable, Hashable {
        let key: String
        let label: String
        var children: [Node] = []
        var id: String { key }
    }

    static let tree: [Node] = [
        Node(key: "consumer", label: "Consumer"),
        Node(key: "government", label: "Government"),
        Node(key: "enterprise", label: "Enterprise", children: [
            Node(key: "agriculture", label: "Agriculture"),
            Node(key: "arts_and_entertainment", label: "Arts & Entertainment"),
            Node(key: "business_services", label: "Business Services"),
            Node(key: "consumer_goods", label: "Consumer Goods"),
            Node(key: "education", label: "Education"),
            Node(key: "energy_and_renewables", label: "Energy & Renewables"),
            Node(key: "financial_services", label: "Financial Services"),
            Node(key: "food_and_hospitality", label: "Food & Hospitality"),
            Node(key: "healthcare", label: "Healthcare"),
            Node(key: "industrials", label: "Industrials"),
            Node(key: "media", label: "Media"),
            Node(key: "real_estate", label: "Real Estate"),
            Node(key: "technology", label: "Technology"),
            Node(key: "telecom_services", label: "Telecom Services"),
            Node(key: "transportation", label: "Transportation"),
        ]),
    ]

    static var allLeaves: [Node] { tree.flatMap { $0.children.isEmpty ? [$0] : $0.children } }

    /// Expands a parent key to its leaves and drops unknown keys.
    static func leafKeys(in keys: [String]) -> [String] {
        var result: [String] = []
        for node in tree {
            if node.children.isEmpty {
                if keys.contains(node.key) { result.append(node.key) }
            } else if keys.contains(node.key) {
                result.append(contentsOf: node.children.map(\.key))
            } else {
                result.append(contentsOf: node.children.map(\.key).filter(keys.contains))
            }
        }
        return result
    }

    /// Chips: a fully selected parent shows as one chip.
    static func summary(_ selected: Set<String>) -> [String] {
        tree.flatMap { node -> [String] in
            if node.children.isEmpty { return selected.contains(node.key) ? [node.label] : [] }
            let chosen = node.children.filter { selected.contains($0.key) }
            return chosen.count == node.children.count ? [node.label] : chosen.map(\.label)
        }
    }
}
