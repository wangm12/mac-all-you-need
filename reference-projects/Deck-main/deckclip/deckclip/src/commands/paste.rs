use anyhow::Result;
use deckclip_core::DeckClient;

use crate::cli::PasteArgs;
use crate::i18n;
use crate::output::OutputMode;

pub async fn run(client: &mut DeckClient, output: OutputMode, args: PasteArgs) -> Result<()> {
    let response = client
        .paste(args.index, args.plain, args.target.as_deref())
        .await?;
    output.print_success(&i18n::t("paste.ok").replace("{}", &args.index.to_string()));
    if let OutputMode::Json = output {
        output.print_response(&response);
    }
    Ok(())
}
