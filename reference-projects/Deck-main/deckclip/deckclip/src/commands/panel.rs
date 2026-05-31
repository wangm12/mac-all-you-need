use anyhow::Result;
use deckclip_core::DeckClient;

use crate::cli::PanelAction;
use crate::i18n;
use crate::output::OutputMode;

pub async fn run(client: &mut DeckClient, output: OutputMode, action: PanelAction) -> Result<()> {
    match action {
        PanelAction::Toggle => {
            let response = client.panel_toggle().await?;
            output.print_success(&i18n::t("panel.toggled"));
            if let OutputMode::Json = output {
                output.print_response(&response);
            }
        }
    }
    Ok(())
}
