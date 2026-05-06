import Foundation
import GRDB

public struct Migration {
    public let identifier: String
    public let migrate: (GRDB.Database) throws -> Void

    public init(identifier: String, migrate: @escaping (GRDB.Database) throws -> Void) {
        self.identifier = identifier
        self.migrate = migrate
    }
}
