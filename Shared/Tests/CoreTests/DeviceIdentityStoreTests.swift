@testable import Core
import XCTest

final class DeviceIdentityStoreTests: XCTestCase {
    func testLoadsExistingPrimaryDeviceID() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let expected = DeviceID.generate()
        try expected.rawValue.write(
            to: root.appendingPathComponent("device-id.txt"),
            atomically: true,
            encoding: .utf8
        )

        let actual = try DeviceIdentityStore.loadOrCreate(root: root)

        XCTAssertEqual(actual, expected)
    }

    func testPrefersRecoveryDeviceIDWhenPresent() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let primary = DeviceID.generate()
        let recovery = DeviceID.generate()
        try primary.rawValue.write(
            to: root.appendingPathComponent("device-id.txt"),
            atomically: true,
            encoding: .utf8
        )
        try recovery.rawValue.write(
            to: root.appendingPathComponent("device-id-recovery.txt"),
            atomically: true,
            encoding: .utf8
        )

        let actual = try DeviceIdentityStore.loadOrCreate(root: root)

        XCTAssertEqual(actual, recovery)
    }

    func testWritesPrimaryDeviceIDWhenMissing() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let actual = try DeviceIdentityStore.loadOrCreate(root: root)
        let stored = try String(
            contentsOf: root.appendingPathComponent("device-id.txt"),
            encoding: .utf8
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(stored, actual.rawValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("device-id-recovery.txt").path))
    }

    func testWritesRecoveryDeviceIDWhenPrimaryReadTimesOut() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let actual = try DeviceIdentityStore.loadOrCreate(
            root: root,
            recoveryURL: root.appendingPathComponent("device-id-recovery.txt"),
            readTimeout: 0.01
        ) { url in
            if url.lastPathComponent == "device-id.txt" {
                Thread.sleep(forTimeInterval: 0.20)
            }
            throw CocoaError(.fileReadNoSuchFile)
        }
        let stored = try String(
            contentsOf: root.appendingPathComponent("device-id-recovery.txt"),
            encoding: .utf8
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(stored, actual.rawValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("device-id.txt").path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mayn-device-id-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
