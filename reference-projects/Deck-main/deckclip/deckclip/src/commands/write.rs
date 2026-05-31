use anyhow::Result;
use deckclip_core::DeckClient;

use crate::cli::WriteArgs;
use crate::i18n;
use crate::output::{read_text_or_stdin, OutputMode};

pub async fn run(client: &mut DeckClient, output: OutputMode, args: WriteArgs) -> Result<()> {
    let text = read_text_or_stdin(args.text)?;
    let response = client
        .write(&text, args.tag.as_deref(), args.tag_id.as_deref(), args.raw)
        .await?;
    output.print_success(&i18n::t("write.ok"));
    if let OutputMode::Json = output {
        output.print_response(&response);
    }
    Ok(())
}
