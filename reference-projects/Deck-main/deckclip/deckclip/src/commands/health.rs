use anyhow::Result;
use deckclip_core::DeckClient;

use crate::i18n;
use crate::output::OutputMode;

pub async fn run(client: &mut DeckClient, output: OutputMode) -> Result<()> {
    let response = client.health().await?;
    output.print_success(&i18n::t("health.ok"));
    if let OutputMode::Json = output {
        output.print_response(&response);
    }
    Ok(())
}
