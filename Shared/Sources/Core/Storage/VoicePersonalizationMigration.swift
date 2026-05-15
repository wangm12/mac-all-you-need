import Foundation

enum VoicePersonalizationMigration {
    static let sql = """
        CREATE TABLE IF NOT EXISTS voice_personalization_contexts (
            id TEXT PRIMARY KEY NOT NULL,
            bundle_id TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            asr_model_id TEXT,
            auto_submit_key TEXT,
            custom_prompt_override TEXT,
            style_notes TEXT,
            encrypted_summary BLOB,
            summary_source_count INTEGER NOT NULL DEFAULT 0,
            summary_generated_at INTEGER,
            sample_count INTEGER NOT NULL DEFAULT 0,
            last_learned_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS voice_personalization_samples (
            id TEXT PRIMARY KEY NOT NULL,
            context_id TEXT NOT NULL,
            transcript_id TEXT,
            encrypted_payload BLOB NOT NULL,
            observed_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL,
            summarized INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(context_id) REFERENCES voice_personalization_contexts(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_personalization_samples_ctx_obs
            ON voice_personalization_samples(context_id, observed_at DESC);
        CREATE INDEX IF NOT EXISTS idx_personalization_samples_expires
            ON voice_personalization_samples(expires_at);
        CREATE INDEX IF NOT EXISTS idx_personalization_samples_unsummarized
            ON voice_personalization_samples(context_id, observed_at DESC)
            WHERE summarized = 0;

        DROP TABLE IF EXISTS app_profiles;
    """
}
