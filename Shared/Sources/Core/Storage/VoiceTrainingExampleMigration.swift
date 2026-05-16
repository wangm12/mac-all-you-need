import Foundation

enum VoiceTrainingExampleMigration {
    static let sql = """
        CREATE TABLE IF NOT EXISTS voice_training_examples (
            id TEXT PRIMARY KEY NOT NULL,
            transcript_id TEXT NOT NULL UNIQUE,
            app_bundle_id TEXT,
            language TEXT NOT NULL,
            model_identifier TEXT NOT NULL,
            audio_path TEXT,
            encrypted_payload BLOB NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY(transcript_id) REFERENCES voice_transcripts(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_voice_training_examples_created_at
            ON voice_training_examples(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_voice_training_examples_app
            ON voice_training_examples(app_bundle_id, created_at DESC);
    """
}
