use anyhow::Result;
use deckclip_core::DeckClient;

use crate::output::OutputMode;

pub async fn run(client: &mut DeckClient, output: OutputMode) -> Result<()> {
    let response = client.read().await?;
    output.print_response(&response);
    Ok(())
}
