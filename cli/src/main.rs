use linkrypt_cli::cmd;
use linkrypt_cli::theme;
use linkrypt_cli::CreateArgs;

use clap::Parser;

// `env!("CARGO_BIN_NAME")` is set by Cargo at compile time to the
// `[[bin]]` target's name (`linkrypt`), so clap's help/version strings
// advertise the correct name without hardcoding it here.
#[derive(Parser, Debug)]
#[command(
    name = env!("CARGO_BIN_NAME"),
    version = concat!(
        env!("CARGO_PKG_VERSION"),
        " (commit ", env!("LINKRYPT_GIT_COMMIT"),
        ", built ",  env!("LINKRYPT_BUILD_DATE"), ")"
    ),
    about = "End-to-end-encrypted share CLI",
)]
struct Cli {
    #[arg(long, global = true, env = "NO_COLOR")]
    no_color: bool,

    #[arg(long, short, global = true)]
    verbose: bool,

    #[arg(long, global = true, env = "LINKRYPT_API_URL")]
    url: Option<String>,

    #[command(subcommand)]
    command: Command,
}

#[derive(clap::Subcommand, Debug)]
enum Command {
    /// Save your API token to config
    Login {
        #[arg(long)]
        url: Option<String>,
    },
    /// Remove the saved API token
    Logout,
    /// Probe /api/healthz
    Healthz,
    /// List your active shares
    List,
    /// Revoke a share by id
    Revoke { id: String },
    /// Show recent audit events
    Audit {
        #[arg(long)]
        limit: Option<u32>,
    },
    /// Create a new share
    Create(CreateArgs),
    /// Manage named environment profiles (prod / staging / dev)
    Env {
        #[command(subcommand)]
        cmd: EnvCommand,
    },
}

#[derive(clap::Subcommand, Debug)]
enum EnvCommand {
    /// List profiles (current is marked with *)
    List,
    /// Switch the current profile
    Use { name: String },
    /// Add a profile and switch to it (prompts for its token)
    Add {
        name: String,
        #[arg(long)]
        url: Option<String>,
    },
    /// Remove a non-current profile
    Remove { name: String },
}

fn main() -> std::process::ExitCode {
    let cli = Cli::parse();
    let theme =
        theme::Theme::with_overrides(cli.no_color, std::env::var_os("FORCE_COLOR").is_some());

    let result = match cli.command {
        Command::Login { url } => cmd::login::run(url.or(cli.url), &theme),
        Command::Logout => cmd::logout::run(&theme),
        Command::Healthz => cmd::healthz::run(cli.url, cli.verbose, &theme),
        Command::List => cmd::list::run(cli.url, cli.verbose, &theme),
        Command::Revoke { id } => cmd::revoke::run(cli.url, id, cli.verbose, &theme),
        Command::Audit { limit } => cmd::audit::run(cli.url, limit, cli.verbose, &theme),
        Command::Create(args) => cmd::create::run(cli.url, args, cli.verbose, &theme),
        Command::Env { cmd } => match cmd {
            EnvCommand::List => cmd::env::list(&theme),
            EnvCommand::Use { name } => cmd::env::use_profile(&name, &theme),
            // Deliberately NOT url.or(cli.url): the global --url doubles as
            // LINKRYPT_API_URL, and persisting an ambient env override into a
            // new profile would be surprising.
            EnvCommand::Add { name, url } => cmd::env::add(&name, url, &theme),
            EnvCommand::Remove { name } => cmd::env::remove(&name, &theme),
        },
    };

    match result {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("{} {}", theme.error("✗"), e);
            std::process::ExitCode::from(e.exit_code() as u8)
        }
    }
}
