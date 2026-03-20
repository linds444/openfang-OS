//! openfang-ctl — OpenFang OS System Control Tool
//!
//! Usage:
//!   openfang-ctl status
//!   openfang-ctl agents list|start|stop|restart <name>
//!   openfang-ctl config get|set|edit <key> [value]
//!   openfang-ctl logs [agent-name] [-f]
//!   openfang-ctl ask <question>
//!   openfang-ctl generate-token
//!   openfang-ctl update

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use colored::Colorize;
use comfy_table::{Cell, CellAlignment, Color, Table};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;

const OPENFANG_API: &str = "http://127.0.0.1:8080";
const CONFIG_PATH: &str = "/etc/openfang/config.toml";

// ─── CLI Definition ───────────────────────────────────────────────────────────

#[derive(Parser)]
#[command(
    name = "openfang-ctl",
    about = "OpenFang OS system control tool",
    version = "0.1.0",
    long_about = None,
)]
struct Cli {
    /// OpenFang API URL
    #[arg(long, default_value = OPENFANG_API, env = "OPENFANG_API")]
    api: String,

    /// Auth token
    #[arg(long, env = "OPENFANG_TOKEN")]
    token: Option<String>,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Show system and agent status
    Status,

    /// Manage agents
    Agents {
        #[command(subcommand)]
        action: AgentAction,
    },

    /// Manage configuration
    Config {
        #[command(subcommand)]
        action: ConfigAction,
    },

    /// View logs
    Logs {
        /// Agent name (omit for system logs)
        agent: Option<String>,
        /// Follow logs
        #[arg(short, long)]
        follow: bool,
        /// Number of lines to show
        #[arg(short = 'n', long, default_value = "50")]
        lines: usize,
    },

    /// Ask the AI assistant a question
    Ask {
        /// Your question
        question: Vec<String>,
    },

    /// Generate a new API auth token
    GenerateToken,

    /// Update OpenFang and system packages
    Update {
        /// Only check for updates, don't apply
        #[arg(long)]
        check: bool,
    },

    /// Show system information
    Info,
}

#[derive(Subcommand)]
enum AgentAction {
    /// List all agents and their status
    List,
    /// Start an agent
    Start { name: String },
    /// Stop an agent
    Stop { name: String },
    /// Restart an agent
    Restart { name: String },
    /// Start all agents
    StartAll,
    /// Stop all agents
    StopAll,
    /// Show agent logs
    Logs { name: String, #[arg(short, long)] follow: bool },
    /// Show detailed agent info
    Info { name: String },
}

#[derive(Subcommand)]
enum ConfigAction {
    /// Get a config value
    Get { key: String },
    /// Set a config value
    Set { key: String, value: String },
    /// Open config in editor
    Edit,
    /// Show full config (redacted secrets)
    Show,
    /// Validate config
    Validate,
}

// ─── API Types ────────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct HealthResponse {
    status: String,
    version: String,
    uptime_secs: u64,
}

#[derive(Deserialize, Clone)]
struct AgentInfo {
    name: String,
    description: String,
    status: String,
    last_run: Option<String>,
    next_run: Option<String>,
    runs_total: u64,
    errors_total: u64,
}

#[derive(Deserialize)]
struct AgentsResponse {
    agents: Vec<AgentInfo>,
}

#[derive(Serialize)]
struct AgentActionRequest {
    action: String,
}

#[derive(Deserialize)]
struct ActionResponse {
    success: bool,
    message: String,
}

#[derive(Serialize)]
struct AskRequest {
    question: String,
    context: String,
}

#[derive(Deserialize)]
struct AskResponse {
    answer: String,
}

// ─── Controller ───────────────────────────────────────────────────────────────

struct Ctl {
    api: String,
    http: Client,
    token: Option<String>,
}

impl Ctl {
    fn new(api: String, token: Option<String>) -> Result<Self> {
        let http = Client::builder()
            .timeout(Duration::from_secs(30))
            .user_agent("openfang-ctl/0.1.0")
            .build()?;
        Ok(Self { api, http, token })
    }

    fn auth(&self, req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        if let Some(token) = &self.token {
            req.bearer_auth(token)
        } else {
            req
        }
    }

    async fn health(&self) -> Result<HealthResponse> {
        self.auth(self.http.get(format!("{}/health", self.api)))
            .send()
            .await?
            .json()
            .await
            .context("Failed to parse health response")
    }

    async fn agents(&self) -> Result<AgentsResponse> {
        self.auth(self.http.get(format!("{}/agents", self.api)))
            .send()
            .await?
            .json()
            .await
            .context("Failed to parse agents response")
    }

    async fn agent_action(&self, name: &str, action: &str) -> Result<ActionResponse> {
        self.auth(
            self.http
                .post(format!("{}/agents/{}/{}", self.api, name, action)),
        )
        .send()
        .await?
        .json()
        .await
        .context("Failed to parse action response")
    }

    async fn ask(&self, question: &str) -> Result<AskResponse> {
        let req = AskRequest {
            question: question.to_string(),
            context: format!(
                "Running on OpenFang OS. Hostname: {}",
                std::fs::read_to_string("/etc/hostname")
                    .unwrap_or_default()
                    .trim()
                    .to_string()
            ),
        };
        self.auth(self.http.post(format!("{}/ask", self.api)))
            .json(&req)
            .send()
            .await?
            .json()
            .await
            .context("Failed to parse ask response")
    }
}

// ─── Status display ───────────────────────────────────────────────────────────

async fn cmd_status(ctl: &Ctl) -> Result<()> {
    println!("\n{}", "  OpenFang OS — System Status".bold().cyan());
    println!("  {}", "─".repeat(50).dimmed());

    // Health check
    match ctl.health().await {
        Ok(h) => {
            let uptime = humantime::format_duration(Duration::from_secs(h.uptime_secs));
            println!("  {} {}", "Agent Runtime:".bold(), "online".green().bold());
            println!("  {} {}", "Version:".bold(), h.version.cyan());
            println!("  {} {}", "Uptime:".bold(), uptime.to_string().cyan());
        }
        Err(e) => {
            println!("  {} {}", "Agent Runtime:".bold(), "offline".red().bold());
            println!("  {}", format!("  {}", e).dimmed());
            println!();
            println!("  Run: {}", "rc-service openfang start".yellow());
            println!();
            return Ok(());
        }
    }

    // System stats from /proc
    println!();
    print_system_stats();

    // Agents
    println!();
    println!("  {}", "Agents:".bold());
    match ctl.agents().await {
        Ok(resp) => {
            for agent in &resp.agents {
                let status_colored = match agent.status.as_str() {
                    "running" => agent.status.green().bold(),
                    "stopped" => agent.status.red().bold(),
                    "error"   => agent.status.red().bold(),
                    _         => agent.status.yellow().bold(),
                };
                println!(
                    "    {:20} {}  (runs: {}, errors: {})",
                    agent.name.cyan(),
                    status_colored,
                    agent.runs_total,
                    if agent.errors_total > 0 {
                        agent.errors_total.to_string().red().to_string()
                    } else {
                        "0".into()
                    }
                );
            }
        }
        Err(_) => println!("    {}", "(could not fetch agent list)".dimmed()),
    }

    println!();
    Ok(())
}

fn print_system_stats() {
    // Memory
    if let Ok(meminfo) = std::fs::read_to_string("/proc/meminfo") {
        let get = |key: &str| -> u64 {
            meminfo
                .lines()
                .find(|l| l.starts_with(key))
                .and_then(|l| l.split_whitespace().nth(1))
                .and_then(|v| v.parse().ok())
                .unwrap_or(0)
        };
        let total = get("MemTotal:") * 1024;
        let avail = get("MemAvailable:") * 1024;
        let used  = total.saturating_sub(avail);
        let pct   = if total > 0 { used * 100 / total } else { 0 };
        println!(
            "  {} {}/{} ({}%)",
            "Memory:".bold(),
            bytesize::ByteSize(used),
            bytesize::ByteSize(total),
            pct
        );
    }

    // Load average
    if let Ok(load) = std::fs::read_to_string("/proc/loadavg") {
        let parts: Vec<&str> = load.split_whitespace().collect();
        if parts.len() >= 3 {
            println!(
                "  {} {} {} {}",
                "Load avg:".bold(),
                parts[0].cyan(),
                parts[1].cyan(),
                parts[2].cyan()
            );
        }
    }

    // Disk
    let disk = std::process::Command::new("df")
        .args(["-h", "/"])
        .output()
        .ok();
    if let Some(out) = disk {
        if let Ok(s) = std::str::from_utf8(&out.stdout) {
            if let Some(line) = s.lines().nth(1) {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 5 {
                    println!(
                        "  {} {}/{} used ({})",
                        "Disk (/):".bold(),
                        parts[2].cyan(),
                        parts[1].cyan(),
                        parts[4].cyan()
                    );
                }
            }
        }
    }
}

async fn cmd_agents(ctl: &Ctl, action: AgentAction) -> Result<()> {
    match action {
        AgentAction::List => {
            let resp = ctl.agents().await?;
            let mut table = Table::new();
            table.set_header(vec!["Name", "Status", "Runs", "Errors", "Last Run", "Next Run"]);

            for agent in &resp.agents {
                let status_cell = match agent.status.as_str() {
                    "running" => Cell::new("● running").fg(Color::Green),
                    "stopped" => Cell::new("○ stopped").fg(Color::Red),
                    "error"   => Cell::new("✗ error").fg(Color::Red),
                    _         => Cell::new(&agent.status).fg(Color::Yellow),
                };

                table.add_row(vec![
                    Cell::new(&agent.name),
                    status_cell,
                    Cell::new(agent.runs_total).set_alignment(CellAlignment::Right),
                    Cell::new(agent.errors_total).set_alignment(CellAlignment::Right),
                    Cell::new(agent.last_run.as_deref().unwrap_or("-")),
                    Cell::new(agent.next_run.as_deref().unwrap_or("-")),
                ]);
            }

            println!("{table}");
        }

        AgentAction::Start { name } => {
            print!("Starting {}...", name.cyan());
            let resp = ctl.agent_action(&name, "start").await?;
            println!(" {}", if resp.success { "OK".green() } else { resp.message.red() });
        }

        AgentAction::Stop { name } => {
            print!("Stopping {}...", name.cyan());
            let resp = ctl.agent_action(&name, "stop").await?;
            println!(" {}", if resp.success { "OK".green() } else { resp.message.red() });
        }

        AgentAction::Restart { name } => {
            print!("Restarting {}...", name.cyan());
            let resp = ctl.agent_action(&name, "restart").await?;
            println!(" {}", if resp.success { "OK".green() } else { resp.message.red() });
        }

        AgentAction::StartAll => {
            println!("Starting all agents...");
            let resp = ctl.agents().await?;
            for agent in &resp.agents {
                print!("  {}...", agent.name.cyan());
                let r = ctl.agent_action(&agent.name, "start").await?;
                println!(" {}", if r.success { "OK".green() } else { r.message.yellow() });
            }
        }

        AgentAction::StopAll => {
            println!("Stopping all agents...");
            let resp = ctl.agents().await?;
            for agent in &resp.agents {
                print!("  {}...", agent.name.cyan());
                let r = ctl.agent_action(&agent.name, "stop").await?;
                println!(" {}", if r.success { "OK".green() } else { r.message.yellow() });
            }
        }

        AgentAction::Logs { name, follow } => {
            let log_path = format!("/var/log/openfang/agents/{}.log", name);
            if follow {
                std::process::Command::new("tail")
                    .args(["-f", &log_path])
                    .status()?;
            } else {
                std::process::Command::new("tail")
                    .args(["-n", "100", &log_path])
                    .status()?;
            }
        }

        AgentAction::Info { name } => {
            let resp = ctl.agents().await?;
            match resp.agents.iter().find(|a| a.name == name) {
                Some(agent) => {
                    println!("{}", "Agent Information".bold().cyan());
                    println!("  Name:        {}", agent.name.cyan());
                    println!("  Description: {}", agent.description);
                    println!("  Status:      {}", agent.status);
                    println!("  Runs:        {}", agent.runs_total);
                    println!("  Errors:      {}", agent.errors_total);
                    println!("  Last run:    {}", agent.last_run.as_deref().unwrap_or("-"));
                    println!("  Next run:    {}", agent.next_run.as_deref().unwrap_or("-"));
                }
                None => eprintln!("Agent not found: {}", name.red()),
            }
        }
    }
    Ok(())
}

async fn cmd_config(action: ConfigAction) -> Result<()> {
    match action {
        ConfigAction::Get { key } => {
            let content = std::fs::read_to_string(CONFIG_PATH)
                .context("Cannot read config")?;
            // Simple TOML key lookup
            for line in content.lines() {
                if line.trim_start().starts_with(&format!("{} =", key.split('.').last().unwrap_or(&key)))
                    || line.trim_start().starts_with(&format!("{}=", key.split('.').last().unwrap_or(&key)))
                {
                    let value = line.split('=').skip(1).collect::<Vec<_>>().join("=").trim().to_string();
                    println!("{} = {}", key.cyan(), value);
                    return Ok(());
                }
            }
            println!("{}", format!("Key '{}' not found", key).yellow());
        }

        ConfigAction::Set { key, value } => {
            let content = std::fs::read_to_string(CONFIG_PATH)
                .context("Cannot read config")?;
            let leaf = key.split('.').last().unwrap_or(&key);
            let new_content: Vec<String> = content
                .lines()
                .map(|line| {
                    if line.trim_start().starts_with(&format!("{} =", leaf))
                        || line.trim_start().starts_with(&format!("{}=", leaf))
                    {
                        format!("{} = \"{}\"", leaf, value)
                    } else {
                        line.to_string()
                    }
                })
                .collect();
            std::fs::write(CONFIG_PATH, new_content.join("\n") + "\n")
                .context("Cannot write config")?;
            println!("Set {} = {}", key.cyan(), value.green());
        }

        ConfigAction::Edit => {
            let editor = std::env::var("EDITOR").unwrap_or_else(|_| "nano".into());
            std::process::Command::new(&editor)
                .arg(CONFIG_PATH)
                .status()
                .context("Failed to open editor")?;
        }

        ConfigAction::Show => {
            let content = std::fs::read_to_string(CONFIG_PATH)
                .context("Cannot read config")?;
            // Redact secrets
            for line in content.lines() {
                if line.contains("api_key") || line.contains("password") || line.contains("token") {
                    let key_part = line.split('=').next().unwrap_or("");
                    println!("{} = {}", key_part, "\"[REDACTED]\"".dimmed());
                } else {
                    println!("{}", line);
                }
            }
        }

        ConfigAction::Validate => {
            let content = std::fs::read_to_string(CONFIG_PATH)
                .context("Cannot read config")?;
            match toml::from_str::<toml::Value>(&content) {
                Ok(_) => println!("{}", "Config is valid TOML.".green()),
                Err(e) => {
                    eprintln!("{} {}", "Config validation failed:".red().bold(), e);
                    std::process::exit(1);
                }
            }
        }
    }
    Ok(())
}

async fn cmd_logs(agent: Option<String>, follow: bool, lines: usize) -> Result<()> {
    let log_path = match agent {
        Some(name) => format!("/var/log/openfang/agents/{}.log", name),
        None       => "/var/log/openfang/openfang.log".to_string(),
    };

    let mut args = vec!["-n".to_string(), lines.to_string(), log_path.clone()];
    if follow {
        args.insert(0, "-f".to_string());
    }

    std::process::Command::new("tail")
        .args(&args)
        .status()
        .with_context(|| format!("Cannot read log: {}", log_path))?;

    Ok(())
}

async fn cmd_ask(ctl: &Ctl, question: Vec<String>) -> Result<()> {
    let q = question.join(" ");
    println!("{}", "  Asking AI assistant...".dimmed());
    match ctl.ask(&q).await {
        Ok(resp) => {
            println!("\n{}\n{}\n", "  Answer:".cyan().bold(), resp.answer);
        }
        Err(e) => {
            eprintln!("{} {}", "Error:".red(), e);
            eprintln!("{}", "Make sure OpenFang is running and configured.".dimmed());
        }
    }
    Ok(())
}

fn cmd_info() {
    println!("{}", "\n  OpenFang OS System Information".bold().cyan());
    println!("  {}", "─".repeat(40).dimmed());

    // OS info
    if let Ok(content) = std::fs::read_to_string("/etc/os-release") {
        for line in content.lines() {
            if line.starts_with("PRETTY_NAME") {
                let v = line.split('=').nth(1).unwrap_or("").trim_matches('"');
                println!("  {} {}", "OS:".bold(), v.cyan());
            }
        }
    }

    // Kernel
    if let Ok(out) = std::process::Command::new("uname").args(["-r"]).output() {
        if let Ok(v) = std::str::from_utf8(&out.stdout) {
            println!("  {} {}", "Kernel:".bold(), v.trim().cyan());
        }
    }

    // Architecture
    if let Ok(out) = std::process::Command::new("uname").args(["-m"]).output() {
        if let Ok(v) = std::str::from_utf8(&out.stdout) {
            println!("  {} {}", "Arch:".bold(), v.trim().cyan());
        }
    }

    // Hostname
    if let Ok(h) = std::fs::read_to_string("/etc/hostname") {
        println!("  {} {}", "Hostname:".bold(), h.trim().cyan());
    }

    // Uptime
    if let Ok(u) = std::fs::read_to_string("/proc/uptime") {
        if let Some(secs) = u.split_whitespace().next().and_then(|s| s.parse::<f64>().ok()) {
            let uptime = humantime::format_duration(Duration::from_secs(secs as u64));
            println!("  {} {}", "Uptime:".bold(), uptime.to_string().cyan());
        }
    }

    println!();
    print_system_stats();
    println!();
}

fn cmd_generate_token() {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    use std::time::{SystemTime, UNIX_EPOCH};

    let mut hasher = DefaultHasher::new();
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos()
        .hash(&mut hasher);
    std::process::id().hash(&mut hasher);
    let token = format!("ofk_{:016x}", hasher.finish());
    println!("Generated token: {}", token.cyan().bold());
    println!();
    println!("Add to /etc/openfang/config.toml:");
    println!("  {}", format!("auth_token = \"{}\"", token).yellow());
    println!();
    println!("Or set environment variable: {}", format!("export OPENFANG_TOKEN={}", token).yellow());
}

// ─── Main ─────────────────────────────────────────────────────────────────────

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let ctl = Ctl::new(cli.api, cli.token)?;

    match cli.command {
        Commands::Status => cmd_status(&ctl).await?,
        Commands::Agents { action } => cmd_agents(&ctl, action).await?,
        Commands::Config { action } => cmd_config(action).await?,
        Commands::Logs { agent, follow, lines } => cmd_logs(agent, follow, lines).await?,
        Commands::Ask { question } => cmd_ask(&ctl, question).await?,
        Commands::GenerateToken => cmd_generate_token(),
        Commands::Info => cmd_info(),
        Commands::Update { check } => {
            if check {
                println!("Checking for updates...");
                std::process::Command::new("apk").args(["update"]).status()?;
                std::process::Command::new("apk").args(["list", "--upgradeable"]).status()?;
            } else {
                println!("{}", "Updating OpenFang OS...".cyan());
                std::process::Command::new("apk").args(["update"]).status()?;
                std::process::Command::new("apk").args(["upgrade"]).status()?;
                println!("{}", "Update complete.".green());
            }
        }
    }

    Ok(())
}
