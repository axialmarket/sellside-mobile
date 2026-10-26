//
//  Geography.swift
//  Axial Mobile
//

import Foundation

/// fe-app's geography constants and the helpers project setup uses from
/// them. The tables themselves are in GeographyData.swift.
enum Geography {
    struct Region: Hashable { let id: Int; let name: String; let order: Int; let elements: [String] }
    struct Country: Hashable { let code: String; let id: Int; let name: String; let region: Int }
    struct Subdivision: Hashable { let code: String; let id: Int; let name: String; let region: Int }

    static let usCountryID = 1
    static let caCountryID = 12
    static let usRegionIDs = [2, 3, 4, 5, 6, 7, 8, 9, 10]
    static let caRegionIDs = [26, 27]

    static func country(code: String) -> Country? { countries.first { $0.code == code } }
    static func region(id: Int) -> Region? { regions.first { $0.id == id } }

    /// Countries for the HQ picker, alphabetised by name.
    static var sortedCountries: [Country] { countries.sorted { $0.name < $1.name } }

    static func subdivisions(forCountry code: String) -> [Subdivision] {
        switch code {
        case "US": usStates.sorted { $0.name < $1.name }
        case "CA": caProvinces.sorted { $0.name < $1.name }
        default: []
        }
    }

    static func hasSubdivisions(_ countryCode: String) -> Bool {
        countryCode == "US" || countryCode == "CA"
    }

    // MARK: HQ

    /// `resolveLocationFromIntent`: a state id, a province id, a country id,
    /// or the US by default.
    static func location(fromGeographyID id: Int?) -> (country: String, state: String) {
        guard let id else { return ("US", "") }
        if let state = usStates.first(where: { $0.id == id }) { return ("US", state.code) }
        if let province = caProvinces.first(where: { $0.id == id }) { return ("CA", province.code) }
        if let country = countries.first(where: { $0.id == id }) { return (country.code, "") }
        return ("US", "")
    }

    /// `getGeography(state, country)`: the most specific id we have.
    static func geographies(state: String, country: String) -> [Int] {
        if !state.isEmpty {
            let list = country == "CA" ? caProvinces : usStates
            if let match = list.first(where: { $0.code == state }) { return [match.id] }
        }
        if let match = Geography.country(code: country) { return [match.id] }
        return []
    }

    /// The teaser preview — `GeographyByIdPipe` with a disclosure level.
    static func displayName(state: String, country: String, disclosure: String) -> String? {
        if !state.isEmpty {
            let list = country == "CA" ? caProvinces : usStates
            guard let subdivision = list.first(where: { $0.code == state }) else { return nil }
            switch disclosure {
            case "state": return subdivision.name
            case "region":
                guard let region = region(id: subdivision.region) else { return nil }
                let elements = region.elements.joined(separator: ", ")
                return country == "US" ? "US - \(region.name) (\(elements))" : "\(region.name) (\(elements))"
            default: return Geography.country(code: country)?.name
            }
        }
        guard let match = Geography.country(code: country) else { return nil }
        // Outside North America the teaser shows the super-region, not the country.
        if match.region != 0, let region = region(id: match.region) { return region.name }
        return match.name
    }

    /// Any id — country, region or leaf — as a chip label.
    static func label(forID id: Int) -> String {
        if let country = countries.first(where: { $0.id == id }) { return country.name }
        if let region = region(id: id) { return region.name }
        if let state = (usStates + caProvinces).first(where: { $0.id == id }) { return state.name }
        return "Area \(id)"
    }

    // MARK: Location filter tree (sharing preferences)

    struct TierNode: Identifiable, Hashable {
        let id: Int
        let label: String
        var children: [TierNode] = []

        var leafIDs: [Int] { children.isEmpty ? [id] : children.flatMap(\.leafIDs) }
    }

    /// `TIERED_GEOGRAPHY_LOCAL`: US and Canada, by region, leaves sorted.
    static let localTiers: [TierNode] = [
        tier(country: usCountryID, regions: usRegionIDs, states: usStates),
        tier(country: caCountryID, regions: caRegionIDs, states: caProvinces),
    ]

    /// `TIERED_GEOGRAPHY_INTERNATIONAL`: the super-regions, flat.
    static let internationalTiers: [TierNode] = regions
        .filter { !([0] + usRegionIDs + caRegionIDs).contains($0.id) }
        .map { TierNode(id: $0.id, label: $0.name) }

    private static func tier(country: Int, regions regionIDs: [Int], states: [Subdivision]) -> TierNode {
        let name = countries.first { $0.id == country }?.name ?? ""
        let ordered = regions.filter { regionIDs.contains($0.id) }
        return TierNode(id: country, label: name, children: ordered.map { region in
            TierNode(id: region.id, label: region.name, children: states
                .filter { $0.region == region.id }
                .sorted { $0.name < $1.name }
                .map { TierNode(id: $0.id, label: $0.name) })
        })
    }

    /// `emitValue`: all of a country → its id; all of a region → the
    /// region's id; otherwise the leaves. International leaves stay as is.
    static func rolledUp(_ leaves: Set<Int>) -> [Int] {
        var result: [Int] = []
        for country in localTiers {
            if Set(country.leafIDs).isSubset(of: leaves) {
                result.append(country.id)
                continue
            }
            for region in country.children {
                let ids = Set(region.leafIDs)
                if ids.isSubset(of: leaves) { result.append(region.id) }
                else { result.append(contentsOf: region.leafIDs.filter(leaves.contains)) }
            }
        }
        result.append(contentsOf: internationalTiers.map(\.id).filter(leaves.contains))
        return result
    }

    /// Hydration: rolled-up ids back to leaves.
    static func leaves(for ids: [Int]) -> Set<Int> {
        var leaves: Set<Int> = []
        for id in ids {
            if let node = (localTiers + localTiers.flatMap(\.children)).first(where: { $0.id == id }) {
                leaves.formUnion(node.leafIDs)
            } else {
                leaves.insert(id)
            }
        }
        return leaves
    }
}
