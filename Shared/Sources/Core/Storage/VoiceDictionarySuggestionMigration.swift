import Foundation

enum VoiceDictionarySuggestionMigration {
    static let sql = """
        CREATE TABLE IF NOT EXISTS voice_dictionary_suggestions (
            id TEXT PRIMARY KEY NOT NULL,
            phrase TEXT NOT NULL,
            replacement TEXT NOT NULL,
            norm_key TEXT NOT NULL,
            occurrences INTEGER NOT NULL DEFAULT 1,
            status TEXT NOT NULL DEFAULT 'pending',
            first_seen_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_dict_suggestions_norm_key
            ON voice_dictionary_suggestions(norm_key);
        CREATE INDEX IF NOT EXISTS idx_dict_suggestions_status_occ
            ON voice_dictionary_suggestions(status, occurrences DESC);
    """
}
