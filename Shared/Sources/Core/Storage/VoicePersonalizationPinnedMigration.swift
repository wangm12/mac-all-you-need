import Foundation

enum VoicePersonalizationPinnedMigration {
    static let sql = """
        CREATE TABLE IF NOT EXISTS voice_personalization_pinned_examples (
            id TEXT PRIMARY KEY NOT NULL,
            context_id TEXT NOT NULL,
            before_text TEXT NOT NULL,
            after_text TEXT NOT NULL,
            is_starred INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            FOREIGN KEY(context_id) REFERENCES voice_personalization_contexts(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_pinned_examples_ctx_sort
            ON voice_personalization_pinned_examples(context_id, sort_order ASC, created_at ASC);
    """
}
