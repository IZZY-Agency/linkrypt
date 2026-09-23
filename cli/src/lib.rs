pub mod api;
pub mod cmd;
pub mod config;
pub mod crypto;
pub mod error;
pub mod input;
pub mod progress;
pub mod theme;

/// CLI args for the `create` subcommand. Defined here so both the binary
/// (`main.rs`) and integration tests can reference it via `linkrypt_cli::CreateArgs`.
#[derive(clap::Args, Debug)]
pub struct CreateArgs {
    pub text: Option<String>,

    #[arg(long)]
    pub file: Option<std::path::PathBuf>,

    #[arg(long, default_value = "7d", value_parser = ["1h", "24h", "7d", "30d"])]
    pub expires: String,

    #[arg(long, default_value_t = 1, value_parser = clap::value_parser!(u32).range(1..=100))]
    pub opens: u32,

    #[arg(long)]
    pub label: Option<String>,

    #[arg(long, num_args = 0..=1, default_missing_value = "")]
    pub passphrase: Option<String>,

    #[arg(long)]
    pub to: Option<String>,

    #[arg(long)]
    pub notify_on_open: bool,

    #[arg(long)]
    pub filename: Option<String>,

    #[arg(long)]
    pub plain: bool,

    #[arg(long)]
    pub json: bool,
}
