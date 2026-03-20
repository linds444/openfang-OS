# OpenFang OS — Agent System

## What Are Agents?

Agents are autonomous AI workers that run on schedules or in response to events. Unlike chatbots (which only respond when you ask), agents work continuously in the background.

OpenFang OS ships with three built-in agents and an easy way to add your own.

---

## Built-in Agents

### system-monitor
**Schedule**: Every minute
**Config**: `/etc/openfang/agents/system-monitor.toml`
**Log**: `/var/log/openfang/agents/system-monitor.log`

Monitors:
- CPU usage (warns at 80%, critical at 95%)
- Memory usage (warns at 85%, critical at 95%)
- Disk usage (warns at 80%, critical at 90%)
- Load average
- Network errors
- Top resource-consuming processes

Uses GPT-4o-mini (fast + cheap) to analyze metrics and determine if alerts are needed.

```bash
# View system-monitor logs
openfang-ctl logs system-monitor

# Adjust thresholds
openfang-ctl config edit  # edit [thresholds] section in agent config
```

### security-guard
**Schedule**: Every 5 minutes
**Config**: `/etc/openfang/agents/security-guard.toml`
**Log**: `/var/log/openfang/agents/security-guard.log`

Monitors:
- SSH brute-force attempts → auto-bans IPs
- Auth log anomalies
- File integrity (critical system files)
- Unexpected open ports
- CVE database (daily)

```bash
# View security events
openfang-ctl logs security-guard

# See banned IPs
cat /var/log/openfang/agents/security-guard-bans.log

# Unban an IP
nft delete element inet openfang_firewall blocked_ips { 1.2.3.4 }
```

### ai-assistant
**Schedule**: On-demand
**Config**: `/etc/openfang/agents/ai-assistant.toml`
**Log**: `/var/log/openfang/agents/ai-assistant.log`

The interactive AI assistant. Access via:
- `openfang-ctl ask "your question"`
- `help "your question"` (in aish)
- REST API: `POST http://localhost:8080/ask`

Uses GPT-4o (capable model) for complex questions, scripting help, and research.

---

## Managing Agents

```bash
# List all agents
openfang-ctl agents list

# Start/stop/restart
openfang-ctl agents start system-monitor
openfang-ctl agents stop security-guard
openfang-ctl agents restart ai-assistant

# Start/stop all
openfang-ctl agents start-all
openfang-ctl agents stop-all

# Detailed info
openfang-ctl agents info system-monitor

# View agent logs
openfang-ctl agents logs security-guard
openfang-ctl agents logs security-guard -f  # follow
```

---

## Creating Custom Agents

Create a TOML config in `/etc/openfang/agents/`:

### Minimal Agent

```toml
# /etc/openfang/agents/hello.toml

[agent]
name        = "hello"
description = "A simple hello world agent"
enabled     = true
schedule    = "*/10 * * * *"  # Every 10 minutes

[llm]
model       = "gpt-4o-mini"
max_tokens  = 128
temperature = 0.5
system_prompt = "You are a cheerful assistant. Say hello and share an interesting fact."
```

### Web Monitor Agent

```toml
# /etc/openfang/agents/web-monitor.toml

[agent]
name        = "web-monitor"
description = "Monitors a website and alerts if it goes down"
enabled     = true
schedule    = "*/5 * * * *"

[llm]
model       = "gpt-4o-mini"
max_tokens  = 256
system_prompt = """
You monitor a website's health. Given the HTTP response data, determine:
1. Is the site up? (status 200-299 = up)
2. Is the response time acceptable? (< 2s = ok, > 5s = slow)
3. Any error patterns in the content?
Respond in JSON: {"status": "up|down|degraded", "latency_ms": 123, "issues": [...]}
"""

[http]
url     = "https://your-site.com"
method  = "GET"
timeout = 10

[alerts]
on_status = ["down", "degraded"]
webhook   = "https://hooks.slack.com/..."
```

### Log Analysis Agent

```toml
# /etc/openfang/agents/log-analyzer.toml

[agent]
name        = "log-analyzer"
description = "Analyzes application logs for errors and anomalies"
enabled     = true
schedule    = "0 * * * *"  # Every hour

[llm]
model       = "gpt-4o-mini"
max_tokens  = 512
system_prompt = """
Analyze the provided log lines. Identify:
1. Error patterns
2. Unusual spikes in activity
3. Security concerns
Respond with a concise summary and severity level (ok/warning/critical).
"""

[input]
type  = "file"
path  = "/var/log/myapp/app.log"
lines = 500  # Last N lines

[alerts]
on_severity = ["warning", "critical"]
log_file    = "/var/log/openfang/agents/log-analyzer.log"
```

### Activate a Custom Agent

```bash
# After creating the config file:
rc-service openfang restart

# Or hot-reload without restart:
openfang-ctl agents reload

# Check it appears
openfang-ctl agents list
```

---

## Agent Configuration Reference

### `[agent]` section
| Key | Type | Description |
|-----|------|-------------|
| `name` | string | Unique agent identifier |
| `description` | string | Human-readable description |
| `enabled` | bool | Whether to run this agent |
| `schedule` | string | Cron expression (empty = on-demand) |
| `on_demand` | bool | Respond to manual triggers |

### `[llm]` section
| Key | Type | Description |
|-----|------|-------------|
| `model` | string | LLM model to use |
| `max_tokens` | int | Maximum response tokens |
| `temperature` | float | 0.0 = deterministic, 1.0 = creative |
| `system_prompt` | string | Agent persona/instructions |

### `[alerts]` section
| Key | Type | Description |
|-----|------|-------------|
| `email` | string | Alert email address |
| `webhook` | string | Webhook URL for alerts |
| `log_file` | string | Log file path |
| `cooldown_minutes` | int | Minimum minutes between alerts |

---

## Agent API

The OpenFang runtime exposes a REST API at `http://localhost:8080`:

```bash
# List agents
curl http://localhost:8080/agents

# Get agent status
curl http://localhost:8080/agents/system-monitor

# Start agent
curl -X POST http://localhost:8080/agents/system-monitor/start

# Stop agent
curl -X POST http://localhost:8080/agents/system-monitor/stop

# Ask the assistant
curl -X POST http://localhost:8080/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "How is my system performing?"}'

# Health check
curl http://localhost:8080/health
```

Add authentication:
```bash
# Generate token
openfang-ctl generate-token

# Use token
curl -H "Authorization: Bearer ofk_abc123..." http://localhost:8080/agents
```
