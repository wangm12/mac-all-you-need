import Foundation

public enum DeviceIdentityStore {
    public static func loadOrCreate(root: URL = AppGroup.containerURL()) throws -> DeviceID {
        let url = root.appendingPathComponent("device-id.txt")
        if let raw = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let id = DeviceID(rawValue: raw)
        {
            return id
        }
        let id = DeviceID.generate()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try id.rawValue.write(to: url, atomically: true, encoding: .utf8)
        return id
    }
}
