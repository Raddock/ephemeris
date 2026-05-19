import XCTest
@testable import Ephemeris

final class AnnotationTests: XCTestCase {

    func test_annotation_codableRoundTrip() throws {
        let rigId = UUID()
        let annotation = Annotation(
            rigProfileId: rigId,
            nightRecordId: UUID(),
            eventDate: Date(timeIntervalSince1970: 1_700_000_000),
            categories: [.equipment, .calibration],
            label: "OAG damaged and replaced",
            detail: "Found a hairline crack in the prism. Swapped to the spare OAG and ran a fresh calibration.",
            isRigMutating: true
        )
        let data = try JSONEncoder().encode(annotation)
        let decoded = try JSONDecoder().decode(Annotation.self, from: data)
        XCTAssertEqual(decoded.rigProfileId, rigId)
        XCTAssertEqual(decoded.label, "OAG damaged and replaced")
        XCTAssertEqual(decoded.categories, [.equipment, .calibration])
        XCTAssertTrue(decoded.isRigMutating)
    }

    func test_annotationCategory_hasDisplayNamesAndSymbols() {
        for category in AnnotationCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty, "\(category) missing displayName")
            XCTAssertFalse(category.symbolName.isEmpty, "\(category) missing SF Symbol")
        }
    }
}
