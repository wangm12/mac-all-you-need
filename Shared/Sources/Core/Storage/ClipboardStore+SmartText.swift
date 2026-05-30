import Foundation
import GRDB

/// Smart Text (migration 008) read/write helpers split out of `ClipboardStore`
/// to keep the core type within length limits. These operate on the
/// `detected_type`, `ocr_text`, and `embedding` columns.
public extension ClipboardStore {
    /// Single-record metadata fetch. Convenience for enrichment paths that
    /// process one record id at a time.
    func meta(for id: RecordID) throws -> ClipboardItemMeta? {
        try metas(for: [id]).first
    }

    func setDetectedType(id: RecordID, json: String?) throws {
        try db.queue.write { conn in
            try conn.execute(
                sql: "UPDATE clipboard_records SET detected_type = ? WHERE id = ?",
                arguments: [json, id.rawValue]
            )
        }
    }

    func setOCRText(id: RecordID, text: String?) throws {
        try db.queue.write { conn in
            try conn.execute(
                sql: "UPDATE clipboard_records SET ocr_text = ? WHERE id = ?",
                arguments: [text, id.rawValue]
            )
        }
    }

    func setEmbedding(id: RecordID, blob: Data?) throws {
        try db.queue.write { conn in
            try conn.execute(
                sql: "UPDATE clipboard_records SET embedding = ? WHERE id = ?",
                arguments: [blob, id.rawValue]
            )
        }
    }

    /// Records that have not yet been embedded for semantic search, newest-first.
    func idsMissingEmbedding(limit: Int) throws -> [RecordID] {
        try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT id FROM clipboard_records
                WHERE embedding IS NULL
                ORDER BY modified DESC LIMIT ?
                """, arguments: [limit]).compactMap { RecordID(rawValue: $0["id"]) }
        }
    }

    /// Image records whose OCR text has not yet been computed, newest-first.
    func idsMissingOCR(limit: Int) throws -> [RecordID] {
        try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT id FROM clipboard_records
                WHERE ocr_text IS NULL AND preview LIKE '(image %'
                ORDER BY modified DESC LIMIT ?
                """, arguments: [limit]).compactMap { RecordID(rawValue: $0["id"]) }
        }
    }
}
