//! aish — AI Shell for OpenFang OS
//!
//! A natural-language-aware shell that:
//! - Passes regular shell commands straight to the system shell
//! - Detects natural language input and converts it to shell commands via LLM
//! - Confirms destructive commands before executing
//! - Integrates with the OpenFang agent runtime

use anyhow::{Context, Result};
use colored::Colorize;
use regex::Regex;
use reqwest::Client;
use rustyline::error::ReadlineError;
use rustyline::history::FileHistory;
use rustyline::{CompletionType, Config, EditMode, Editor};
use serde::{Deserialize, Serialize};
use std::env;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

// ─── Configuration ────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize, Clone)]
struct AishConfig {
    #[serde(default)]
    llm: LlmConfig,
    #[serde(default)]
    aish: AishBehavior,
}

#[derive(Debug, Deserialize, Clone)]
struct LlmConfig {
    #[serde(default = "default_provider")]
    provider: String,
    #[serde(default)]
    api_key: String,
    #[serde(default = "default_base_url")]
    base_url: String,
    #[serde(default = "default_model")]
    model: String,
    #[serde(default = "default_timeout")]
    timeout: u64,
}

#[derive(Debug, Deserialize, Clone, Default)]
struct AishBehavior {
    #[serde(default = "default_true")]
    confirm_before_run: bool,
    #[serde(default = "default_true")]
    confirm_destructive: bool,
    #[serde(default = "default_true")]
    show_generated_cmd: bool,
    #[serde(default = "default_max_tokens")]
    max_tokens: u32,
    #[serde(default)]
    system_prompt: String,
}

fn default_provider() -> String { "openai".into() }
fn default_model() -> String { "gpt-4o-mini".into() }
fn default_base_url() -> String { "https://api.openai.com/v1".into() }
fn default_timeout() -> u64 { 30 }
fn default_max_tokens() -> u32 { 512 }
fn default_true() -> bool { true }

impl Default for LlmConfig {
    fn default() -> Self {
        Self {
            provider: default_provider(),
            api_key: env::var("OPENAI_API_KEY").unwrap_or_default(),
            base_url: default_base_url(),
            model: default_model(),
            timeout: default_timeout(),
        }
    }
}

impl Default for AishConfig {
    fn default() -> Self {
        Self {
            llm: LlmConfig::default(),
            aish: AishBehavior::default(),
        }
    }
}

// ─── OpenAI API types ─────────────────────────────────────────────────────────

#[derive(Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<ChatMessage>,
    max_tokens: u32,
    temperature: f32,
}

#[derive(Serialize, Deserialize, Clone)]
struct ChatMessage {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct ChatResponse {
    choices: Vec<ChatChoice>,
}

#[derive(Deserialize)]
struct ChatChoice {
    message: ChatMessage,
}

// ─── Shell ────────────────────────────────────────────────────────────────────

/// Patterns that strongly indicate natural language (not a shell command)
const NL_INDICATORS: &[&str] = &[
    "show me", "find all", "list all", "how do i", "how to", "what is",
    "what are", "can you", "please", "i want to", "i need to", "help me",
    "explain", "create a", "make a", "delete all", "remove all", "compress",
    "convert", "search for", "look for", "give me", "tell me",
];

/// Patterns for destructive commands that need confirmation
const DESTRUCTIVE_PATTERNS: &[&str] = &[
    r"rm\s+-rf?\s",
    r"rm\s+.*\*",
    r"dd\s+.*of=",
    r"mkfs\.",
    r"fdisk\s",
    r"parted\s",
    r"shred\s",
    r"truncate\s",
    r"wipefs\s",
    r">\s*/dev/",
    r"chmod\s+-R\s+777",
    r"chown\s+-R\s+.*:.*\s+/",
    r"sudo\s+rm\s",
    r"pkill\s+-9",
    r"kill\s+-9\s+1\b",
];

struct Shell {
    config: AishConfig,
    http: Client,
    history: Vec<ChatMessage>,
    destructive_re: Vec<Regex>,
}

impl Shell {
    fn new(config: AishConfig) -> Result<Self> {
        let http = Client::builder()
            .timeout(Duration::from_secs(config.llm.timeout))
            .user_agent("aish/0.1.0 OpenFang-OS")
            .build()?;

        let destructive_re = DESTRUCTIVE_PATTERNS
            .iter()
            .map(|p| Regex::new(p))
            .collect::<Result<Vec<_>, _>>()
            .context("Failed to compile destructive patterns")?;

        Ok(Self {
            config,
            http,
            history: Vec::new(),
            destructive_re,
        })
    }

    /// Detect if input looks like natural language rather than a shell command.
    fn is_natural_language(&self, input: &str) -> bool {
        let lower = input.to_lowercase();

        // If it starts with a common NL indicator, it's NL
        for indicator in NL_INDICATORS {
            if lower.starts_with(indicator) || lower.contains(&format!(" {} ", indicator)) {
                return true;
            }
        }

        // Heuristic: if the first "word" is not a known binary path and the
        // input has >= 3 words with no special shell characters, treat as NL.
        let has_shell_chars = input.contains('|')
            || input.contains('>')
            || input.contains('<')
            || input.contains('$')
            || input.contains('`')
            || input.contains(';')
            || input.contains("&&")
            || input.contains("||");

        if has_shell_chars {
            return false;
        }

        let words: Vec<&str> = input.split_whitespace().collect();
        if words.len() >= 4 {
            // Check if first word is likely a command
            let first = words[0];
            let is_likely_cmd = first.starts_with('/')
                || first.starts_with("./")
                || first.starts_with("../")
                || is_common_command(first);
            return !is_likely_cmd;
        }

        false
    }

    /// Check if command is potentially destructive.
    fn is_destructive(&self, cmd: &str) -> bool {
        if !self.config.aish.confirm_destructive {
            return false;
        }
        for re in &self.destructive_re {
            if re.is_match(cmd) {
                return true;
            }
        }
        false
    }

    /// Ask the LLM to translate natural language to a shell command.
    async fn nl_to_shell(&mut self, input: &str) -> Result<String> {
        let system = if self.config.aish.system_prompt.is_empty() {
            format!(
                "You are an expert Linux shell assistant running on OpenFang OS (Alpine Linux). \
                 Convert the user's natural language request into a single shell command or a short pipeline. \
                 Rules:\n\
                 1. Output ONLY the shell command — no explanation, no markdown, no backticks.\n\
                 2. Use standard Unix tools available on Alpine Linux (busybox, GNU coreutils, etc).\n\
                 3. Make the command safe and minimal.\n\
                 4. If the task requires multiple steps, chain with && or use a one-liner.\n\
                 5. If you cannot produce a safe command, output exactly: CANNOT_HELP\n\
                 Current user: {}\n\
                 Hostname: {}\n\
                 Shell: bash",
                env::var("USER").unwrap_or_else(|_| "ai".into()),
                hostname()
            )
        } else {
            self.config.aish.system_prompt.clone()
        };

        let mut messages = vec![ChatMessage {
            role: "system".into(),
            content: system,
        }];
        // Add recent history for context (last 6 messages)
        let history_start = self.history.len().saturating_sub(6);
        messages.extend_from_slice(&self.history[history_start..]);
        messages.push(ChatMessage {
            role: "user".into(),
            content: input.to_string(),
        });

        let base_url = resolve_base_url(&self.config.llm);

        let req = ChatRequest {
            model: self.config.llm.model.clone(),
            messages,
            max_tokens: self.config.aish.max_tokens,
            temperature: 0.1,
        };

        let mut request = self
            .http
            .post(format!("{}/chat/completions", base_url))
            .json(&req);

        if !self.config.llm.api_key.is_empty() {
            request = request.bearer_auth(&self.config.llm.api_key);
        }

        let resp = request
            .send()
            .await
            .context("Failed to reach LLM API — check your network and API key")?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(anyhow::anyhow!("LLM API error {}: {}", status, body));
        }

        let chat: ChatResponse = resp.json().await.context("Failed to parse LLM response")?;

        let cmd = chat
            .choices
            .into_iter()
            .next()
            .map(|c| c.message.content.trim().to_string())
            .unwrap_or_default();

        // Add to conversation history
        self.history.push(ChatMessage {
            role: "user".into(),
            content: input.to_string(),
        });
        self.history.push(ChatMessage {
            role: "assistant".into(),
            content: cmd.clone(),
        });

        // Cap history at 20 messages
        if self.history.len() > 20 {
            self.history.drain(0..2);
        }

        Ok(cmd)
    }

    /// Execute a shell command and return exit code.
    fn execute(&self, cmd: &str) -> i32 {
        let shell = env::var("SHELL").unwrap_or_else(|_| "/bin/sh".into());
        match Command::new(&shell)
            .arg("-c")
            .arg(cmd)
            .status()
        {
            Ok(status) => status.code().unwrap_or(1),
            Err(e) => {
                eprintln!("{} {}", "error:".red().bold(), e);
                1
            }
        }
    }

    /// Process a single line of input.
    async fn process_line(&mut self, line: &str) -> Result<i32> {
        let line = line.trim();
        if line.is_empty() {
            return Ok(0);
        }

        // Built-in commands
        match line {
            "exit" | "quit" | "logout" => {
                println!("{}", "Goodbye from OpenFang OS.".cyan());
                std::process::exit(0);
            }
            "clear" | "cls" => {
                print!("\x1B[2J\x1B[1;1H");
                return Ok(0);
            }
            "history" => {
                return Ok(self.execute("cat ~/.aish_history 2>/dev/null || true"));
            }
            _ => {}
        }

        // Handle cd specially (must be done in-process)
        if line.starts_with("cd ") || line == "cd" {
            let dir = if line == "cd" {
                dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"))
            } else {
                PathBuf::from(line.trim_start_matches("cd ").trim())
            };
            if let Err(e) = env::set_current_dir(&dir) {
                eprintln!("{} {}: {}", "aish:".red(), dir.display(), e);
                return Ok(1);
            }
            return Ok(0);
        }

        // Detect natural language → convert to shell command
        let cmd_to_run = if self.is_natural_language(line) {
            println!(
                "{}{}",
                "  AI  ".on_cyan().black().bold(),
                " Translating...".dimmed()
            );

            match self.nl_to_shell(line).await {
                Ok(cmd) if cmd == "CANNOT_HELP" => {
                    println!(
                        "{}",
                        "  I can't safely convert that to a shell command.".yellow()
                    );
                    return Ok(1);
                }
                Ok(cmd) => {
                    if self.config.aish.show_generated_cmd {
                        println!("  {} {}", "→".cyan().bold(), cmd.white().bold());
                    }
                    cmd
                }
                Err(e) => {
                    eprintln!("{} {}", "  AI error:".red().bold(), e);
                    eprintln!(
                        "  {}",
                        "Falling back to direct execution...".dimmed()
                    );
                    line.to_string()
                }
            }
        } else {
            line.to_string()
        };

        // Safety check for destructive commands
        if self.is_destructive(&cmd_to_run) {
            println!(
                "\n  {} {}",
                "⚠  DESTRUCTIVE COMMAND:".red().bold(),
                cmd_to_run.yellow()
            );
            print!("  {} ", "Run anyway? [y/N]:".bold());
            use std::io::{self, BufRead, Write};
            io::stdout().flush()?;
            let mut answer = String::new();
            io::stdin().lock().read_line(&mut answer)?;
            if !matches!(answer.trim().to_lowercase().as_str(), "y" | "yes") {
                println!("  {}", "Aborted.".dimmed());
                return Ok(1);
            }
        } else if self.config.aish.confirm_before_run && self.is_natural_language(line) {
            // For AI-generated commands, confirm before running
            print!("  {} ", "[Run? Y/n]:".bold());
            use std::io::{self, BufRead, Write};
            io::stdout().flush()?;
            let mut answer = String::new();
            io::stdin().lock().read_line(&mut answer)?;
            let answer = answer.trim().to_lowercase();
            if answer == "n" || answer == "no" {
                println!("  {}", "Skipped.".dimmed());
                return Ok(0);
            }
        }

        Ok(self.execute(&cmd_to_run))
    }
}

// ─── Utilities ────────────────────────────────────────────────────────────────

fn is_common_command(word: &str) -> bool {
    const CMDS: &[&str] = &[
        "ls", "cd", "cp", "mv", "rm", "mkdir", "rmdir", "touch", "cat", "less", "more",
        "head", "tail", "grep", "find", "awk", "sed", "sort", "uniq", "wc", "cut",
        "echo", "printf", "read", "test", "true", "false", "exit", "export", "unset",
        "alias", "unalias", "source", ".", "bash", "sh", "fish", "zsh",
        "ps", "top", "htop", "kill", "pkill", "killall", "jobs", "fg", "bg", "wait",
        "which", "whereis", "type", "file", "stat", "du", "df", "lsblk",
        "chmod", "chown", "chgrp", "umask",
        "tar", "zip", "unzip", "gzip", "gunzip", "bzip2", "xz", "zstd",
        "curl", "wget", "ssh", "scp", "rsync", "nc", "netstat", "ss", "ip",
        "ping", "traceroute", "dig", "host", "nslookup",
        "apt", "apk", "dnf", "yum", "pacman", "brew",
        "git", "make", "cargo", "rustc", "python3", "python", "node", "npm",
        "vim", "vi", "nano", "emacs", "code",
        "systemctl", "service", "rc-service", "journalctl",
        "sudo", "su", "doas",
        "openfang-ctl", "openfang", "aish",
    ];
    CMDS.contains(&word)
}

fn resolve_base_url(llm: &LlmConfig) -> String {
    if !llm.base_url.is_empty() {
        return llm.base_url.trim_end_matches('/').to_string();
    }
    match llm.provider.as_str() {
        "anthropic" => "https://api.anthropic.com/v1".into(),
        "ollama"    => "http://localhost:11434/v1".into(),
        "openrouter" => "https://openrouter.ai/api/v1".into(),
        "groq"      => "https://api.groq.com/openai/v1".into(),
        "mistral"   => "https://api.mistral.ai/v1".into(),
        _           => "https://api.openai.com/v1".into(),
    }
}

fn hostname() -> String {
    std::fs::read_to_string("/etc/hostname")
        .unwrap_or_else(|_| "openfang".into())
        .trim()
        .to_string()
}

fn build_prompt() -> String {
    let user = env::var("USER").unwrap_or_else(|_| "ai".into());
    let host = hostname();
    let cwd  = env::current_dir()
        .map(|p| {
            let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/home/ai"));
            if p.starts_with(&home) {
                format!("~{}", p.strip_prefix(&home).unwrap().display())
            } else {
                p.display().to_string()
            }
        })
        .unwrap_or_else(|_| "?".into());

    format!("[{}@{} {}]$ ", user.cyan(), host.cyan(), cwd.blue())
}

fn load_config() -> AishConfig {
    // Try /etc/openfang/config.toml, then ~/.aish_config
    let paths = [
        PathBuf::from("/etc/openfang/config.toml"),
        dirs::home_dir()
            .unwrap_or_default()
            .join(".aish_config"),
    ];

    for path in &paths {
        if path.exists() {
            if let Ok(content) = std::fs::read_to_string(path) {
                if let Ok(cfg) = toml::from_str::<AishConfig>(&content) {
                    return cfg;
                }
            }
        }
    }

    // Fall back to env vars
    let mut cfg = AishConfig::default();
    if let Ok(key) = env::var("OPENAI_API_KEY") {
        cfg.llm.api_key = key;
    }
    if let Ok(key) = env::var("ANTHROPIC_API_KEY") {
        cfg.llm.api_key = key;
        cfg.llm.provider = "anthropic".into();
    }
    if let Ok(model) = env::var("AISH_MODEL") {
        cfg.llm.model = model;
    }
    cfg
}

// ─── Main ─────────────────────────────────────────────────────────────────────

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging (AISH_LOG=debug to enable)
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_env("AISH_LOG")
                .unwrap_or_else(|_| "aish=warn".parse().unwrap()),
        )
        .init();

    let config = load_config();
    let mut shell = Shell::new(config)?;

    // Check if running a single command (aish -c "...")
    let args: Vec<String> = env::args().collect();
    if args.len() >= 3 && args[1] == "-c" {
        let cmd = args[2..].join(" ");
        let exit_code = shell.process_line(&cmd).await?;
        std::process::exit(exit_code);
    }

    // Print banner
    if env::var("AISH_NO_BANNER").is_err() {
        println!(
            "{}",
            "  aish — OpenFang AI Shell  (type 'help' for AI help, 'exit' to quit)".cyan().dimmed()
        );
        // Show LLM status
        if shell.config.llm.api_key.is_empty()
            && shell.config.llm.provider != "ollama"
        {
            println!(
                "  {}",
                "⚠  No API key set. AI features disabled. Set via: openfang-ctl config set llm.api_key <key>"
                    .yellow()
            );
        } else {
            println!(
                "  {} {} / {}",
                "✓ AI:".green().bold(),
                shell.config.llm.provider.cyan(),
                shell.config.llm.model.cyan()
            );
        }
        println!();
    }

    // Set up readline
    let history_path = dirs::home_dir()
        .unwrap_or_default()
        .join(".aish_history");

    let rl_config = Config::builder()
        .history_ignore_space(true)
        .completion_type(CompletionType::List)
        .edit_mode(EditMode::Emacs)
        .max_history_size(10000)
        .expect("valid history size")
        .build();

    let mut rl: Editor<(), FileHistory> = Editor::with_config(rl_config)?;
    let _ = rl.load_history(&history_path);

    // ─── REPL ─────────────────────────────────────────────────────────────────
    loop {
        let prompt = build_prompt();
        match rl.readline(&prompt) {
            Ok(line) => {
                let line = line.trim().to_string();
                if !line.is_empty() {
                    rl.add_history_entry(&line)?;
                }
                let _ = rl.save_history(&history_path);
                let _ = shell.process_line(&line).await;
            }
            Err(ReadlineError::Interrupted) => {
                // Ctrl-C: cancel current input
                println!();
                continue;
            }
            Err(ReadlineError::Eof) => {
                // Ctrl-D: exit
                println!("{}", "logout".dimmed());
                break;
            }
            Err(e) => {
                eprintln!("{} {}", "readline error:".red(), e);
                break;
            }
        }
    }

    Ok(())
}
