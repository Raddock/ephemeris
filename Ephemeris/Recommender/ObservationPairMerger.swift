//
//  ObservationPairMerger.swift
//  Ephemeris
//
//  Copyright (C) 2026 Andrew Burwell
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import Foundation

/// One row in the observations panel: a single observation, or an RA + Dec pair
/// of the same finding folded into one card.
///
/// The recommender runs per axis, so a condition affecting both axes ("RA
/// corrections appear sluggish" + "Dec corrections appear sluggish") arrives as
/// two observations. That is the right granularity for storage and MCP, but in
/// the UI it doubles the card count and reads as two independent problems when
/// it is one condition with two measurements. Pairing happens here, at display
/// time only — nothing persisted changes.
nonisolated struct ObservationDisplayItem: Identifiable, Sendable {
    /// The higher-severity member of the pair (or the sole observation).
    let primary: RecommenderObservation
    /// The other axis's observation when the same finding fired on both.
    let paired: RecommenderObservation?

    var id: UUID { primary.id }

    /// Collapsed-row title. Paired items drop the axis prefix and carry an
    /// explicit "RA + Dec" tag so the merge is visible, not hidden.
    var title: String {
        guard paired != nil else { return primary.title }
        return "\(Self.strippingAxisPrefix(primary.title).capitalizedFirstLetter) · RA + Dec"
    }

    /// Highest severity across the pair — the card must not read calmer than
    /// its worst member.
    var severity: RecommenderObservation.Severity {
        max(primary.severity, paired?.severity ?? primary.severity)
    }

    var sourceAuthority: SourceAuthority { primary.sourceAuthority }

    /// The RA-axis member of a pair, identified by title prefix.
    var raObservation: RecommenderObservation? {
        guard paired != nil else { return nil }
        return [primary, paired!].first { $0.title.hasPrefix("RA ") }
    }

    /// The Dec-axis member of a pair, identified by title prefix.
    var decObservation: RecommenderObservation? {
        guard paired != nil else { return nil }
        return [primary, paired!].first { $0.title.hasPrefix("Dec ") }
    }

    /// Union of both members' contributors, first-occurrence order, deduped —
    /// the causes are usually identical between axes and must not repeat.
    var candidateContributors: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for c in primary.candidateContributors + (paired?.candidateContributors ?? []) {
            if seen.insert(c).inserted { out.append(c) }
        }
        return out
    }

    var relatedPHD2Tools: [PHD2Tool] {
        var seen = Set<PHD2Tool>()
        var out: [PHD2Tool] = []
        for t in primary.relatedPHD2Tools + (paired?.relatedPHD2Tools ?? []) {
            if seen.insert(t).inserted { out.append(t) }
        }
        return out
    }

    static func strippingAxisPrefix(_ title: String) -> String {
        if title.hasPrefix("RA ") { return String(title.dropFirst(3)) }
        if title.hasPrefix("Dec ") { return String(title.dropFirst(4)) }
        return title
    }
}

nonisolated enum ObservationPairMerger {

    /// Fold per-axis pairs into single display items. An observation pairs with
    /// another when both titles start with an axis token ("RA " / "Dec "), the
    /// remainder of the title matches exactly, and the category matches — the
    /// generators are in-repo, so the title format is a controlled contract
    /// (pinned by tests). Order is preserved: a merged item sits where its
    /// first member appeared, and the higher-severity member leads.
    static func displayItems(from observations: [RecommenderObservation]) -> [ObservationDisplayItem] {
        var consumed = Set<UUID>()
        var items: [ObservationDisplayItem] = []

        for (index, obs) in observations.enumerated() {
            if consumed.contains(obs.id) { continue }

            guard isAxisPrefixed(obs.title) else {
                items.append(ObservationDisplayItem(primary: obs, paired: nil))
                continue
            }

            let strippedTitle = ObservationDisplayItem.strippingAxisPrefix(obs.title)
            let partner = observations.dropFirst(index + 1).first { candidate in
                !consumed.contains(candidate.id) &&
                isAxisPrefixed(candidate.title) &&
                candidate.title.prefix(3) != obs.title.prefix(3) &&   // opposite axis
                candidate.category == obs.category &&
                ObservationDisplayItem.strippingAxisPrefix(candidate.title) == strippedTitle
            }

            if let partner {
                consumed.insert(partner.id)
                let (lead, follow) = partner.severity > obs.severity ? (partner, obs) : (obs, partner)
                items.append(ObservationDisplayItem(primary: lead, paired: follow))
            } else {
                items.append(ObservationDisplayItem(primary: obs, paired: nil))
            }
        }
        return items
    }

    private static func isAxisPrefixed(_ title: String) -> Bool {
        title.hasPrefix("RA ") || title.hasPrefix("Dec ")
    }
}

nonisolated extension String {
    var capitalizedFirstLetter: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
