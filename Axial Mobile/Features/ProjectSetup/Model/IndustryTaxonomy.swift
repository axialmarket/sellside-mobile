//
//  IndustryTaxonomy.swift
//  Axial Mobile
//

import Foundation

/// The industry taxonomy — `GET /taxonomy` (Accept `application/json;v=3`),
/// grouped by vertical × activity. industry.api.service.ts and
/// industry-selector.helpers.ts.
enum IndustryTaxonomy {
    static let verticals: [Int: String] = [
        1: "Agriculture", 2: "Arts & Entertainment", 3: "Business Services", 4: "Consumer Goods", 5: "Education",
        6: "Energy & Renewables", 7: "Financial Services", 8: "Food & Hospitality", 9: "Industrials",
        10: "Healthcare", 11: "Media", 12: "Real Estate", 13: "Technology", 14: "Telecom Services", 15: "Transportation",
    ]

    static let activities: [Int: String] = [
        1: "Construction", 2: "Distribution/Wholesale", 3: "Information/Software", 4: "Maintenance/Repair",
        5: "Manufacturing", 6: "Raw Materials", 7: "Rental & Leasing", 8: "Retail", 9: "Services",
    ]

    struct Node: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
        let children: [Node]

        enum CodingKeys: String, CodingKey { case id, name, children }

        init(id: Int, name: String, children: [Node] = []) {
            self.id = id; self.name = name; self.children = children
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            children = (try? c.decodeIfPresent([Node].self, forKey: .children)) ?? []
        }

        /// 0 for a leaf.
        var height: Int { children.map { $0.height + 1 }.max() ?? 0 }
        var descendants: [Node] { children.flatMap { [$0] + $0.descendants } }
        var leafCount: Int { children.isEmpty ? 1 : children.map(\.leafCount).reduce(0, +) }
    }

    struct Group: Decodable, Identifiable, Hashable {
        let vertical: Int
        let activity: Int
        let trees: [Node]

        var id: String { "\(vertical):\(activity)" }
        var verticalName: String { IndustryTaxonomy.verticals[vertical] ?? "Vertical \(vertical)" }
        var activityName: String { IndustryTaxonomy.activities[activity] ?? "Activity \(activity)" }
        var industryCount: Int { trees.map { 1 + $0.descendants.count }.reduce(0, +) }

        /// "Industrials + Manufacturing (12 industries)".
        var title: String {
            "\(verticalName) + \(activityName) (\(industryCount) \(industryCount == 1 ? "industry" : "industries"))"
        }
    }

    struct Response: Decodable {
        let searchResults: [Group]
        enum CodingKeys: String, CodingKey { case searchResults = "search_results" }
    }

    static func query(sourceType: String, sourceID: String, keyword: String) -> [URLQueryItem] {
        let verticalList = "[" + verticals.keys.sorted().map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let activityList = "[" + activities.keys.sorted().map { "\"\($0)\"" }.joined(separator: ",") + "]"
        return [
            URLQueryItem(name: "source_type", value: sourceType),
            URLQueryItem(name: "source_id", value: sourceID),
            URLQueryItem(name: "verticals", value: verticalList),
            URLQueryItem(name: "activities", value: activityList),
            URLQueryItem(name: "query", value: keyword),
        ]
    }

    static let headers = ["Accept": "application/json;v=3"]

    /// Sorted by vertical name, then activity name.
    static func sorted(_ groups: [Group]) -> [Group] {
        groups.filter { !$0.trees.isEmpty }.sorted {
            ($0.verticalName, $0.activityName) < ($1.verticalName, $1.activityName)
        }
    }
}

/// The supply-side selection rules (`toggleManyIndustries`,
/// `rollUpIndustries`), over one vertical × activity group.
enum IndustrySelectionRules {
    /// Sellside picks specific industries: a leaf, or a parent of leaves.
    static func isSelectable(_ node: IndustryTaxonomy.Node) -> Bool { node.height <= 1 }

    static func selection(_ node: IndustryTaxonomy.Node, in group: IndustryTaxonomy.Group) -> IndustrySelection {
        IndustrySelection(vertical: group.vertical, activity: group.activity, industryID: node.id, name: node.name)
    }

    /// The node and its ancestors, root first.
    static func path(to id: Int, in group: IndustryTaxonomy.Group) -> [IndustryTaxonomy.Node]? {
        func search(_ nodes: [IndustryTaxonomy.Node], trail: [IndustryTaxonomy.Node]) -> [IndustryTaxonomy.Node]? {
            for node in nodes {
                if node.id == id { return trail + [node] }
                if let found = search(node.children, trail: trail + [node]) { return found }
            }
            return nil
        }
        return search(group.trees, trail: [])
    }

    private static func isSelected(_ node: IndustryTaxonomy.Node, _ group: IndustryTaxonomy.Group,
                                   _ selected: [IndustrySelection]) -> Bool {
        selected.contains { $0.vertical == group.vertical && $0.activity == group.activity && $0.industryID == node.id }
    }

    /// Checked when it, or anything above it, is selected.
    static func isChecked(_ node: IndustryTaxonomy.Node, in group: IndustryTaxonomy.Group,
                          selected: [IndustrySelection]) -> Bool {
        (path(to: node.id, in: group) ?? [node]).contains { isSelected($0, group, selected) }
    }

    /// Something below it is selected.
    static func isPartial(_ node: IndustryTaxonomy.Node, in group: IndustryTaxonomy.Group,
                          selected: [IndustrySelection]) -> Bool {
        node.descendants.contains { isSelected($0, group, selected) }
    }

    static func toggle(_ node: IndustryTaxonomy.Node, in group: IndustryTaxonomy.Group,
                       selected: [IndustrySelection]) -> [IndustrySelection] {
        var result = selected
        let inGroup = { (s: IndustrySelection) in s.vertical == group.vertical && s.activity == group.activity }
        let trail = path(to: node.id, in: group) ?? [node]

        if isChecked(node, in: group, selected: selected) {
            if isSelected(node, group, selected) {
                result.removeAll { inGroup($0) && $0.industryID == node.id }
            } else if let ancestorIndex = trail.firstIndex(where: { isSelected($0, group, selected) }) {
                // Unchecking under a selected ancestor: the ancestor goes, and
                // every sibling along the way down comes in instead.
                result.removeAll { inGroup($0) && $0.industryID == trail[ancestorIndex].id }
                for level in ancestorIndex..<(trail.count - 1) {
                    let onPath = trail[level + 1].id
                    for sibling in trail[level].children where sibling.id != onPath {
                        result.append(selection(sibling, in: group))
                    }
                }
            }
            return result
        }

        if isPartial(node, in: group, selected: selected) {
            let ids = Set(node.descendants.map(\.id))
            result.removeAll { inGroup($0) && ids.contains($0.industryID ?? -1) }
            return result
        }

        // Adding: descendants fold into it, then full sets roll up.
        let ids = Set(node.descendants.map(\.id))
        result.removeAll { inGroup($0) && ids.contains($0.industryID ?? -1) }
        result.append(selection(node, in: group))
        return rollUp(result, along: trail, in: group)
    }

    /// Whenever every child of a node is selected, the node replaces them.
    private static func rollUp(_ selected: [IndustrySelection], along trail: [IndustryTaxonomy.Node],
                               in group: IndustryTaxonomy.Group) -> [IndustrySelection] {
        var result = selected
        for parent in trail.dropLast().reversed() {
            let childIDs = Set(parent.children.map(\.id))
            let chosen = result.filter {
                $0.vertical == group.vertical && $0.activity == group.activity && childIDs.contains($0.industryID ?? -1)
            }
            guard !childIDs.isEmpty, chosen.count == childIDs.count else { break }
            result.removeAll { s in chosen.contains(s) }
            result.append(selection(parent, in: group))
        }
        return result
    }
}
