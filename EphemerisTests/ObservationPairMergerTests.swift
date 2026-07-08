import Testing
import Foundation
@testable import Ephemeris

/// The pair merger folds per-axis findings into one display item. Its contract:
/// only true RA/Dec pairs merge, severity never reads calmer than the worst
/// member, order is preserved, and the title format the generators emit is a
/// pinned contract (these tests fail if a generator changes its title shape).
@Suite("Observation pair merging")
struct ObservationPairMergerTests {

    private func obs(_ title: String,
                     category: RecommenderObservation.Category = .pattern,
                     severity: RecommenderObservation.Severity = .pattern,
                     contributors: [String] = []) -> RecommenderObservation {
        RecommenderObservation(
            scope: .singleNight,
            rigProfileId: UUID(),
            category: category,
            severity: severity,
            title: title,
            summary: "summary for \(title)",
            candidateContributors: contributors,
            suggestedResponse: "response",
            sourceAuthority: .ephemerisHeuristic
        )
    }

    @Test func raDecPairMergesIntoOneItem() {
        let items = ObservationPairMerger.displayItems(from: [
            obs("Dec corrections appear sluggish"),
            obs("RA corrections appear sluggish"),
        ])
        #expect(items.count == 1)
        #expect(items.first?.paired != nil)
        #expect(items.first?.title == "Corrections appear sluggish · RA + Dec")
        #expect(items.first?.raObservation?.title == "RA corrections appear sluggish")
        #expect(items.first?.decObservation?.title == "Dec corrections appear sluggish")
    }

    @Test func unpairedAxisObservationStaysSingle() {
        let items = ObservationPairMerger.displayItems(from: [
            obs("RA corrections appear sluggish"),
            obs("Periodic residual detected at ~575s"),
        ])
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.paired == nil })
        #expect(items.first?.title == "RA corrections appear sluggish")
    }

    @Test func differentFindingsOnOppositeAxesDoNotMerge() {
        let items = ObservationPairMerger.displayItems(from: [
            obs("RA corrections appear sluggish"),
            obs("Dec min-move likely too high — missing real motion"),
        ])
        #expect(items.count == 2)
    }

    @Test func categoryMismatchBlocksMerge() {
        let items = ObservationPairMerger.displayItems(from: [
            obs("RA corrections appear sluggish", category: .pattern),
            obs("Dec corrections appear sluggish", category: .suggestion),
        ])
        #expect(items.count == 2)
    }

    @Test func mergedSeverityIsTheWorstMemberAndLeads() {
        let items = ObservationPairMerger.displayItems(from: [
            obs("RA corrections appear sluggish", severity: .suggestion),
            obs("Dec corrections appear sluggish", severity: .alert),
        ])
        #expect(items.count == 1)
        #expect(items.first?.severity == .alert)
        #expect(items.first?.primary.severity == .alert)
    }

    @Test func orderIsPreservedAroundMerges() {
        let items = ObservationPairMerger.displayItems(from: [
            obs("Guide scale far from imaging scale", category: .suggestion),
            obs("Dec corrections appear sluggish"),
            obs("Periodic residual detected at ~575s", category: .suggestion),
            obs("RA corrections appear sluggish"),
        ])
        #expect(items.map(\.title) == [
            "Guide scale far from imaging scale",
            "Corrections appear sluggish · RA + Dec",
            "Periodic residual detected at ~575s",
        ])
    }

    @Test func contributorsUnionIsDeduped() {
        let items = ObservationPairMerger.displayItems(from: [
            obs("RA corrections appear sluggish", contributors: ["Aggressiveness too low", "Wind"]),
            obs("Dec corrections appear sluggish", contributors: ["Aggressiveness too low", "Backlash"]),
        ])
        #expect(items.first?.candidateContributors == ["Aggressiveness too low", "Wind", "Backlash"])
    }

    @Test func twoSameAxisObservationsNeverMerge() {
        // Two RA findings with identical titles (shouldn't happen, but must not
        // fold into a fake "RA + Dec" pair if it does).
        let items = ObservationPairMerger.displayItems(from: [
            obs("RA corrections appear sluggish"),
            obs("RA corrections appear sluggish"),
        ])
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.paired == nil })
    }
}
