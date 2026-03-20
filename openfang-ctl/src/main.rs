//! openfang-ctl — OpenFang OS System Control Tool (Ubuntu 24.04 LTS)
//!
//! Usage:
//!   openfang-ctl status
//!   openfang-ctl agents list|start|stop|restart|start-all|stop-all
//!   openfang-ctl config get|set|edit|show|validate <key> [value]
//!   openfang-ctl logs [agent-name] [-f] [-n N]
//!   openfang-ctl ask <question>
//!   openfang-ctl generate-token
//!   openfang-ctl update [--check]
//!   openfang-ctl info

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use colored::Colorize;
use comfy_table::{Cell, CellAlignment, Color, Table};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;

const OPENFANG_API: &str = "http://127.0.0.1:8080";
const CONFIG_PATH:  &str = "/etc/openfang/config.toml";

// ─── CLI Definition ───────────────────────────────────────────────────────────

#[derive(Parser)]
#[command(
    name    = "openfang-ctl",
    about   = "OpenFang OS system control tool",
    version = "0.1.0",
)]
struct Cli {
    #[arg(long, default_value = OPENFANG_API, env = "OPENFANG_API")]
    api: String,

    #[arg(long, env = "OPENFANG_TOKEN")]
    token: Option<String>,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Show system and agent status
    Status,
    /// Manage AI agents
    Agents {
        #[command(subcommand)]
        action: AgentAction,
    },
    /// Manage configuration
    Config {
        #[command(subcommand)]
        action: ConfigAction,
    },
    /// View system or agent logs
    Logs {
        agent: Option<String>,
        #[arg(short, long)] follow: bool,
        #[arg(short = 'n', long, default_value = "50")] lines: usize,
    },
    /// Ask the AI assistant a question
    Ask { question: Vec<String> },
    /// Generate a new API auth token
    GenerateToken,
    /// Update OS packages and OpenFang components
    Update {
        /// Dry-run: show available updates without installing
        #[arg(long)] check: bool,
        /// Update OS packages only (skip OpenFang release download)
        #[arg(long)] os_only: bool,
        /// Update OpenFang components only (skip apt)
        #[arg(long)] openfang_only: bool,
    },
    /// Show system information
    Info,
    /// Open the Firefox browser (desktop)
    Browser { url: Option<String> },
    /// Restart a system service (uses systemctl)
    Restart { service: String },
}

#[derive(Subcommand)]
enum AgentAction {
    /// List all agents and status
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
    /// View agent logs
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
    /// Show full config (secrets redacted)
    Show,
    /// Validate config syntax
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
struct AskRequest {
    question: String,
    context: String,
}

#[derive(Deserialize)]
struct AskResponse {
    answer: String,
}

#[derive(Deserialize)]
struct ActionResponse {
    success: bool,
    message: String,
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

    fn auth(&self, r: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        if let Some(t) = &self.token { r.bearer_auth(t) } else { r }
    }

    async fn health(&self) -> Result<HealthResponse> {
        self.auth(self.http.get(format!("{}/health", self.api)))
            .send().await?.json().await.context("health check failed")
    }

    async fn agents(&self) -> Result<AgentsResponse> {
        self.auth(self.http.get(format!("{}/agents", self.api)))
            .send().await?.json().await.context("agents list failed")
    }

    async fn agent_action(&self, name: &str, action: &str) -> Result<ActionResponse> {
        self.auth(self.http.post(format!("{}/agents/{}/{}", self.api, name, action)))
            .send().await?.json().await.context("agent action failed")
    }

    async fn ask(&self, question: &str) -> Result<AskResponse> {
        let req = AskRequest {
            question: question.to_string(),
            context: format!(
                "Running OpenFang OS (Ubuntu 24.04 LTS). Hostname: {}. Shell: aish.",
                hostname()
            ),
        };
        self.auth(self.http.post(format!("{}/ask", self.api)))
            .json(&req).send().await?.json().await.context("ask failed")
    }
}

// ─── Commands ─────────────────────────────────────────────────────────────────

async fn cmd_status(ctl: &Ctl) -> Result<()> {
    println!("\n{}", "  OpenFang OS — System Status".bold().cyan());
    println!("  {}", "─".repeat(52).dimmed());

    // OpenFang API health
    match ctl.health().await {
        Ok(h) => {
            let up = humantime::format_duration(Duration::from_secs(h.uptime_secs));
            println!("  {} {}", "Agent Runtime:".bold(), "online".green().bold());
            println!("  {} v{}", "Version:".bold(), h.version.cyan());
            println!("  {} {}", "Uptime:".bold(), up.to_string().cyan());
        }
        Err(_) => {
            println!("  {} {}", "Agent Runtime:".bold(), "offline".red().bold());
            println!("  {}", "Start: sudo systemctl start openfang".yellow());
        }
    }

    // systemd service status
    println!();
    println!("  {}", "System Services:".bold());
    for svc in &["openfang", "lightdm", "NetworkManager", "ssh", "ufw", "apparmor"] {
        let status = systemd_status(svc);
        let indicator = if status == "active" {
            "●".green().to_string()
        } else {
            "○".red().to_string()
        };
        println!("    {} {:20} {}", indicator, svc.cyan(), status.dimmed());
    }

    // System stats
    println!();
    print_system_stats();

    // Agents
    println!();
    println!("  {}", "AI Agents:".bold());
    match ctl.agents().await {
        Ok(resp) => {
            for agent in &resp.agents {
                let status_c = match agent.status.as_str() {
                    "running" => agent.status.green().bold(),
                    "stopped" => agent.status.red().bold(),
                    "error"   => agent.status.red().bold(),
                    _         => agent.status.yellow().bold(),
                };
                println!(
                    "    {:24} {}  (runs: {}, errors: {})",
                    agent.name.cyan(),
                    status_c,
                    agent.runs_total,
                    if agent.errors_total > 0 {
                        agent.errors_total.to_string().red().to_string()
                    } else { "0".into() }
                );
            }
        }
        Err(_) => println!("    {}", "(API offline — start openfang to see agents)".dimmed()),
    }

    println!();
    Ok(())
}

fn systemd_status(service: &str) -> String {
    std::process::Command::new("systemctl")
        .args(["is-active", "--quiet", service])
        .status()
        .map(|s| if s.success() { "active" } else { "inactive" })
        .unwrap_or("unknown")
        .to_string()
}

fn print_system_stats() {
    // Memory from /proc/meminfo
    if let Ok(m) = std::fs::read_to_string("/proc/meminfo") {
        let get = |key: &str| -> u64 {
            m.lines()
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
    if let Ok(l) = std::fs::read_to_string("/proc/loadavg") {
        let p: Vec<&str> = l.split_whitespace().collect();
        if p.len() >= 3 {
            println!("  {} {} {} {}", "Load avg:".bold(),
                p[0].cyan(), p[1].cyan(), p[2].cyan());
        }
    }

    // Disk
    if let Ok(o) = std::process::Command::new("df").args(["-h", "/"]).output() {
        if let Ok(s) = std::str::from_utf8(&o.stdout) {
            if let Some(line) = s.lines().nth(1) {
                let p: Vec<&str> = line.split_whitespace().collect();
                if p.len() >= 5 {
                    println!("  {} {}/{} used ({})",
                        "Disk (/):".bold(),
                        p[2].cyan(), p[1].cyan(), p[4].cyan());
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
            table.set_header(["Name", "Status", "Runs", "Errors", "Last Run", "Next Run"]);
            for a in &resp.agents {
                let sc = match a.status.as_str() {
                    "running" => Cell::new("● running").fg(Color::Green),
                    "stopped" => Cell::new("○ stopped").fg(Color::Red),
                    "error"   => Cell::new("✗ error").fg(Color::Red),
                    _         => Cell::new(&a.status).fg(Color::Yellow),
                };
                table.add_row([
                    Cell::new(&a.name),
                    sc,
                    Cell::new(a.runs_total).set_alignment(CellAlignment::Right),
                    Cell::new(a.errors_total).set_alignment(CellAlignment::Right),
                    Cell::new(a.last_run.as_deref().unwrap_or("-")),
                    Cell::new(a.next_run.as_deref().unwrap_or("-")),
                ]);
            }
            println!("{table}");
        }
        AgentAction::Start { name } => {
            print!("Starting {}... ", name.cyan());
            let r = ctl.agent_action(&name, "start").await?;
            println!("{}", if r.success { "OK".green() } else { r.message.red() });
        }
        AgentAction::Stop { name } => {
            print!("Stopping {}... ", name.cyan());
            let r = ctl.agent_action(&name, "stop").await?;
            println!("{}", if r.success { "OK".green() } else { r.message.red() });
        }
        AgentAction::Restart { name } => {
            print!("Restarting {}... ", name.cyan());
            let r = ctl.agent_action(&name, "restart").await?;
            println!("{}", if r.success { "OK".green() } else { r.message.red() });
        }
        AgentAction::StartAll => {
            println!("Starting all agents...");
            let resp = ctl.agents().await?;
            for a in &resp.agents {
                print!("  {}... ", a.name.cyan());
                let r = ctl.agent_action(&a.name, "start").await?;
                println!("{}", if r.success { "OK".green() } else { r.message.yellow() });
            }
        }
        AgentAction::StopAll => {
            println!("Stopping all agents...");
            let resp = ctl.agents().await?;
            for a in &resp.agents {
                print!("  {}... ", a.name.cyan());
                let r = ctl.agent_action(&a.name, "stop").await?;
                println!("{}", if r.success { "OK".green() } else { r.message.yellow() });
            }
        }
        AgentAction::Logs { name, follow } => {
            let path = format!("/var/log/openfang/agents/{}.log", name);
            let mut args = vec![if follow { "-f" } else { "-n" }];
            if !follow { args.push("100"); }
            args.push(&path);
            std::process::Command::new("tail").args(&args).status()?;
        }
        AgentAction::Info { name } => {
            let resp = ctl.agents().await?;
            if let Some(a) = resp.agents.iter().find(|x| x.name == name) {
                println!("{}", "Agent Information".bold().cyan());
                println!("  Name:        {}", a.name.cyan());
                println!("  Description: {}", a.description);
                println!("  Status:      {}", a.status);
                println!("  Runs:        {}", a.runs_total);
                println!("  Errors:      {}", a.errors_total);
                println!("  Last run:    {}", a.last_run.as_deref().unwrap_or("-"));
                println!("  Next run:    {}", a.next_run.as_deref().unwrap_or("-"));
            } else {
                eprintln!("Agent not found: {}", name.red());
            }
        }
    }
    Ok(())
}

async fn cmd_config(action: ConfigAction) -> Result<()> {
    match action {
        ConfigAction::Get { key } => {
            let content = std::fs::read_to_string(CONFIG_PATH)
                .context("Cannot read config — try: sudo openfang-ctl config get ...")?;
            let leaf = key.split('.').last().unwrap_or(&key);
            let found = content.lines().find(|l| {
                let t = l.trim_start();
                t.starts_with(&format!("{} =", leaf)) || t.starts_with(&format!("{}=", leaf))
            });
            match found {
                Some(l) => println!("{} ={}", key.cyan(),
                    l.splitn(2, '=').nth(1).unwrap_or("").trim()),
                None => println!("{}", format!("Key '{}' not found", key).yellow()),
            }
        }
        ConfigAction::Set { key, value } => {
            let content = std::fs::read_to_string(CONFIG_PATH)
                .context("Cannot read config")?;
            let leaf = key.split('.').last().unwrap_or(&key);
            let new: Vec<String> = content.lines().map(|l| {
                let t = l.trim_start();
                if t.starts_with(&format!("{} =", leaf)) || t.starts_with(&format!("{}=", leaf)) {
                    format!("{} = \"{}\"", leaf, value)
                } else { l.to_string() }
            }).collect();
            std::fs::write(CONFIG_PATH, new.join("\n") + "\n")
                .context("Cannot write config — try: sudo openfang-ctl config set ...")?;
            println!("Set {} = {}", key.cyan(), value.green());
        }
        ConfigAction::Edit => {
            let editor = std::env::var("EDITOR")
                .or_else(|_| std::env::var("VISUAL"))
                .unwrap_or_else(|_| "mousepad".into());
            std::process::Command::new(&editor).arg(CONFIG_PATH).status()
                .context("Failed to open editor")?;
        }
        ConfigAction::Show => {
            let content = std::fs::read_to_string(CONFIG_PATH)
                .context("Cannot read config")?;
            for line in content.lines() {
                if line.contains("api_key") || line.contains("password") || line.contains("token") {
                    let k = line.splitn(2, '=').next().unwrap_or("").trim();
                    println!("{} = {}", k, "\"[REDACTED]\"".dimmed());
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
                Err(e) => { eprintln!("{} {}", "Validation failed:".red().bold(), e); std::process::exit(1); }
            }
        }
    }
    Ok(())
}

async fn cmd_logs(agent: Option<String>, follow: bool, lines: usize) -> Result<()> {
    let path = match agent {
        Some(name) => format!("/var/log/openfang/agents/{}.log", name),
        None       => "/var/log/openfang/openfang.log".into(),
    };
    let n = lines.to_string();
    let mut args = vec!["-n", &n, &path];
    if follow { args.insert(0, "-f"); }
    std::process::Command::new("tail").args(&args).status()
        .with_context(|| format!("Cannot read: {}", path))?;
    Ok(())
}

async fn cmd_ask(ctl: &Ctl, question: Vec<String>) -> Result<()> {
    let q = question.join(" ");
    println!("{}", "  Asking AI assistant...".dimmed());
    match ctl.ask(&q).await {
        Ok(r) => println!("\n{}\n{}\n", "  Answer:".cyan().bold(), r.answer),
        Err(e) => {
            eprintln!("{} {}", "Error:".red(), e);
            eprintln!("{}", "Make sure OpenFang is running: sudo systemctl start openfang".dimmed());
        }
    }
    Ok(())
}

fn cmd_info() {
    println!("{}", "\n  OpenFang OS — System Information".bold().cyan());
    println!("  {}", "─".repeat(42).dimmed());

    // OS
    if let Ok(c) = std::fs::read_to_string("/etc/os-release") {
        for line in c.lines() {
            if line.starts_with("PRETTY_NAME") {
                println!("  {} {}", "OS:".bold(),
                    line.split('=').nth(1).unwrap_or("").trim_matches('"').cyan());
            }
        }
    }

    // Kernel
    if let Ok(o) = std::process::Command::new("uname").args(["-r"]).output() {
        println!("  {} {}", "Kernel:".bold(),
            std::str::from_utf8(&o.stdout).unwrap_or("").trim().cyan());
    }

    // Architecture
    if let Ok(o) = std::process::Command::new("uname").args(["-m"]).output() {
        println!("  {} {}", "Arch:".bold(),
            std::str::from_utf8(&o.stdout).unwrap_or("").trim().cyan());
    }

    // Hostname
    println!("  {} {}", "Hostname:".bold(), hostname().cyan());

    // Uptime
    if let Ok(u) = std::fs::read_to_string("/proc/uptime") {
        if let Some(s) = u.split_whitespace().next().and_then(|s| s.parse::<f64>().ok()) {
            println!("  {} {}", "Uptime:".bold(),
                humantime::format_duration(Duration::from_secs(s as u64)).to_string().cyan());
        }
    }

    // Desktop
    let display = std::env::var("DISPLAY").unwrap_or_else(|_| "(none)".into());
    let session = std::env::var("XDG_SESSION_TYPE").unwrap_or_else(|_| "tty".into());
    println!("  {} {}", "Display:".bold(), display.cyan());
    println!("  {} {}", "Session:".bold(), session.cyan());

    println!();
    print_system_stats();
    println!();
}

fn cmd_generate_token() {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    use std::time::{SystemTime, UNIX_EPOCH};
    let mut h = DefaultHasher::new();
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos().hash(&mut h);
    std::process::id().hash(&mut h);
    let token = format!("ofk_{:016x}", h.finish());
    println!("Generated token: {}", token.cyan().bold());
    println!("\nAdd to /etc/openfang/config.toml:");
    println!("  {}", format!("[agents.api]\nauth_token = \"{}\"", token).yellow());
}

fn hostname() -> String {
    std::fs::read_to_string("/etc/hostname")
        .unwrap_or_else(|_| "openfang".into())
        .trim().to_string()
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

        Commands::Browser { url } => {
            let u = url.as_deref().unwrap_or("about:newtab");
            std::process::Command::new("firefox").arg(u).spawn()?;
            println!("Opened Firefox: {}", u.cyan());
        }

        Commands::Restart { service } => {
            println!("Restarting {}...", service.cyan());
            let status = std::process::Command::new("sudo")
                .args(["systemctl", "restart", &service])
                .status()?;
            if status.success() {
                println!("{}", "Done.".green());
            } else {
                eprintln!("{}", "Failed to restart service.".red());
            }
        }

        Commands::Update { check, os_only, openfang_only } => {
            const UPDATE_SCRIPT: &str = "/usr/lib/openfang/update.sh";

            if !std::path::Path::new(UPDATE_SCRIPT).exists() {
                eprintln!("{}", format!("Update script not found: {}", UPDATE_SCRIPT).red());
                std::process::exit(1);
            }

            let mut args: Vec<&str> = vec![];
            if check         { args.push("--check"); }
            if os_only       { args.push("--os-only"); }
            if openfang_only { args.push("--openfang-only"); }

            if check {
                println!("{}", "Checking for available updates...".cyan());
            } else {
                println!("{}", "Updating OpenFang OS...".cyan());
                println!("{}", "  (requires root — run: sudo openfang-ctl update)".dimmed());
            }

            let status = std::process::Command::new("bash")
                .arg(UPDATE_SCRIPT)
                .args(&args)
                .status()
                .with_context(|| format!("Failed to run {}", UPDATE_SCRIPT))?;

            std::process::exit(status.code().unwrap_or(1));
        }
    }

    Ok(())
}
