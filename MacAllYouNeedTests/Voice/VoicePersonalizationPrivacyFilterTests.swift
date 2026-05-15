@testable import MacAllYouNeed
import XCTest

final class VoicePersonalizationPrivacyFilterTests: XCTestCase {
    private func metadata(
        bundleID: String? = "com.apple.TextEdit",
        pid: pid_t = 1234,
        role: String? = "AXTextArea",
        subrole: String? = nil,
        isEditable: Bool = true
    ) -> AXTargetMetadata {
        AXTargetMetadata(
            bundleID: bundleID,
            pid: pid,
            role: role,
            subrole: subrole,
            isEditable: isEditable
        )
    }

    func testRejectsMissingBundle() {
        XCTAssertFalse(VoicePersonalizationPrivacyFilter.shouldCapture(metadata(bundleID: nil)))
        XCTAssertFalse(VoicePersonalizationPrivacyFilter.shouldCapture(metadata(bundleID: "")))
    }

    func testRejectsMissingRole() {
        XCTAssertFalse(VoicePersonalizationPrivacyFilter.shouldCapture(metadata(role: nil)))
    }

    func testRejectsRoleNotInAllowlist() {
        XCTAssertFalse(VoicePersonalizationPrivacyFilter.shouldCapture(metadata(role: "AXButton")))
        XCTAssertFalse(VoicePersonalizationPrivacyFilter.shouldCapture(metadata(role: "AXStaticText")))
        XCTAssertFalse(VoicePersonalizationPrivacyFilter.shouldCapture(metadata(role: "AXImage")))
    }

    func testRejectsSecureSubroleEvenWithAllowedRole() {
        XCTAssertFalse(VoicePersonalizationPrivacyFilter.shouldCapture(
            metadata(role: "AXTextField", subrole: "AXSecureTextField")
        ))
    }

    func testRejectsNonEditableElement() {
        XCTAssertFalse(VoicePersonalizationPrivacyFilter.shouldCapture(metadata(isEditable: false)))
    }

    func testAcceptsCommonEditableTextRoles() {
        XCTAssertTrue(VoicePersonalizationPrivacyFilter.shouldCapture(metadata(role: "AXTextField")))
        XCTAssertTrue(VoicePersonalizationPrivacyFilter.shouldCapture(metadata(role: "AXTextArea")))
        XCTAssertTrue(VoicePersonalizationPrivacyFilter.shouldCapture(metadata(role: "AXComboBox")))
    }

    func testRejectsAllDenylistBundlesIndividually() {
        for bundleID in VoicePersonalizationPrivacyFilter.bundleDenyList {
            XCTAssertFalse(
                VoicePersonalizationPrivacyFilter.shouldCapture(metadata(bundleID: bundleID)),
                "deny-list bundle should be rejected: \(bundleID)"
            )
        }
    }

    func testHappyPath() {
        XCTAssertTrue(VoicePersonalizationPrivacyFilter.shouldCapture(metadata()))
    }

    func testIdentityKeyDistinguishesPidAndRoleAndSubrole() {
        let a = metadata(pid: 1, role: "AXTextField", subrole: nil)
        let b = metadata(pid: 1, role: "AXTextField", subrole: nil)
        XCTAssertEqual(a.identityKey, b.identityKey)

        let differentPid = metadata(pid: 2, role: "AXTextField", subrole: nil)
        XCTAssertNotEqual(a.identityKey, differentPid.identityKey)

        let differentRole = metadata(pid: 1, role: "AXTextArea", subrole: nil)
        XCTAssertNotEqual(a.identityKey, differentRole.identityKey)

        let differentSubrole = metadata(pid: 1, role: "AXTextField", subrole: "AXSecureTextField")
        XCTAssertNotEqual(a.identityKey, differentSubrole.identityKey)
    }
}
