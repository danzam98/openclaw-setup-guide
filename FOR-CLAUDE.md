# OpenClaw Setup Guide - Complete Installation Checklist

This is a mechanical, step-by-step guide for setting up OpenClaw with Vertex AI and Docker sandboxing. Follow each phase in order without skipping steps.

**Template Variables Used Throughout:**
- `{{HOME}}` - Your home directory (typically `/Users/username` on macOS)
- `{{GCP_PROJECT_ID}}` - Your Google Cloud project ID
- `{{GCP_REGION}}` - Vertex AI region (e.g., `us-central1`)
- `{{SLACK_BOT_TOKEN}}` - Slack bot OAuth token (starts with `xoxb-`)
- `{{SLACK_APP_TOKEN}}` - Slack app-level token (starts with `xapp-`)
- `{{SLACK_SIGNING_SECRET}}` - Slack signing secret
- `{{ONEPASSWORD_SERVICE_ACCOUNT_TOKEN}}` - 1Password service account token (optional)

---

## Phase 1: Prerequisites Check

> Goal: Verify all required tools are installed before starting OpenClaw installation

### Step 1.1: Check Node.js Version

**Command:**
```bash
node --version
```

**Expected:** `v20.x.x` or higher

**If it fails:**
```bash
# Install via nvm (recommended)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.zshrc  # or ~/.bashrc
nvm install 20
nvm use 20
```

### Step 1.2: Check Docker Installation

**Command:**
```bash
docker --version && docker ps
```

**Expected:** Docker version displayed and empty/running containers list (no errors)

**If it fails:** Install Docker Desktop from https://www.docker.com/products/docker-desktop

### Step 1.3: Check Google Cloud SDK

**Command:**
```bash
gcloud --version
```

**Expected:** Google Cloud SDK version displayed

**If it fails:**
```bash
# macOS
brew install --cask google-cloud-sdk

# Linux
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# Windows
# Download from https://cloud.google.com/sdk/docs/install
```

### Step 1.4: Check Git Installation

**Command:**
```bash
git --version
```

**Expected:** `git version 2.x.x` or higher

**If it fails:**
```bash
# macOS
brew install git

# Linux
sudo apt-get install git  # Debian/Ubuntu
sudo yum install git      # RedHat/CentOS
```

### Step 1.5: Verify PATH Configuration

**Command:**
```bash
echo $PATH | grep -o '/usr/local/bin' && which gcloud
```

**Expected:** `/usr/local/bin` shown and gcloud path displayed

⚠️ **GOTCHA:** LaunchD services on macOS don't inherit your shell's PATH. If `/usr/local/bin` isn't in PATH, gcloud won't be found by the proxy service. We'll fix this in Phase 9.

---

## Phase 2: Install OpenClaw

> Goal: Clone and install OpenClaw core system

### Step 2.1: Clone Repository

**Command:**
```bash
cd {{HOME}}
git clone https://github.com/cyanheads/openclaw.git
cd openclaw
```

**Verify:**
```bash
ls -la | grep "package.json"
```

**Expected:** `package.json` file exists

### Step 2.2: Install Dependencies

**Command:**
```bash
npm install
```

**Expected:** No errors, `node_modules/` directory created

**If it fails:** Check Node.js version (must be 20+) and internet connection

### Step 2.3: Create OpenClaw Directories

**Command:**
```bash
mkdir -p {{HOME}}/.openclaw/workspace
mkdir -p {{HOME}}/.openclaw/sandboxes
mkdir -p {{HOME}}/.openclaw/logs
```

**Verify:**
```bash
ls -la {{HOME}}/.openclaw
```

**Expected:** Three directories: `workspace`, `sandboxes`, `logs`

---

## Phase 3: Google Cloud Setup

> Goal: Configure GCP project and enable Vertex AI API

### Step 3.1: Authenticate with Google Cloud

**Command:**
```bash
gcloud auth login
```

**Expected:** Browser opens for authentication, then shows "You are now logged in"

### Step 3.2: Set Default Project

**Command:**
```bash
gcloud config set project {{GCP_PROJECT_ID}}
```

**Verify:**
```bash
gcloud config get-value project
```

**Expected:** Shows `{{GCP_PROJECT_ID}}`

### Step 3.3: Enable Vertex AI API

**Command:**
```bash
gcloud services enable aiplatform.googleapis.com
```

**Expected:** "Operation finished successfully" or "Service already enabled"

**Verify:**
```bash
gcloud services list --enabled | grep aiplatform
```

**Expected:** `aiplatform.googleapis.com` in the list

### Step 3.4: Configure Application Default Credentials (ADC)

**Command:**
```bash
# CRITICAL: Unset any existing service account credentials
unset GOOGLE_APPLICATION_CREDENTIALS

# Set up ADC
gcloud auth application-default login
```

**Expected:** Browser opens, authenticate, then shows credentials saved to `~/.config/gcloud/application_default_credentials.json`

**Verify:**
```bash
ls -la {{HOME}}/.config/gcloud/application_default_credentials.json
```

**Expected:** File exists

⚠️ **GOTCHA:** If `GOOGLE_APPLICATION_CREDENTIALS` environment variable is set, the proxy will try to use service account auth instead of ADC. Always use ADC for development. Keep service accounts unset unless explicitly needed.

### Step 3.5: Test Vertex AI Access

**Command:**
```bash
gcloud ai models list --region={{GCP_REGION}} --limit=1
```

**Expected:** Shows at least one model or empty list (no permission errors)

**If it fails:** Check project billing is enabled and you have Vertex AI User role

---

## Phase 4: Vertex AI Proxy Setup

> Goal: Install and configure the streaming-capable Vertex AI proxy server

### Step 4.1: Clone Proxy Repository

**Command:**
```bash
cd {{HOME}}
git clone https://github.com/yourusername/vertexai-openai-proxy.git
cd vertexai-openai-proxy
```

⚠️ **NOTE:** Replace with actual proxy repository URL. If using the version from MEMORY.md (commit 18f2bde with streaming support), ensure you have that version.

### Step 4.2: Install Proxy Dependencies

**Command:**
```bash
python3 --version  # Should be 3.8+
pip3 install -r requirements.txt
```

**Expected:** All dependencies installed without errors

**If it fails:**
```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### Step 4.3: Verify Proxy Code Has Streaming Support

**Command:**
```bash
grep -n "client.stream()" app.py
```

**Expected:** Should find line(s) with `client.stream()` method call

⚠️ **GOTCHA:** OpenClaw hardcodes `stream: true` on ALL requests (openai-completions.js:331). The proxy MUST support streaming or all requests will fail. Verify the proxy detects the `stream` parameter and uses:
- `client.stream()` + `aiter_bytes()` for streaming requests (SSE format)
- `client.post()` + `.json()` for non-streaming requests

**If streaming code is missing:**
You need the version with streaming support (commit 18f2bde or later). The proxy must handle both streaming and non-streaming requests.

### Step 4.4: Create Proxy Configuration

**Command:**
```bash
cat > {{HOME}}/vertexai-openai-proxy/config.env << 'EOF'
PORT=8000
GCP_PROJECT_ID={{GCP_PROJECT_ID}}
GCP_REGION={{GCP_REGION}}
DEFAULT_MODEL=gemini-2.0-flash-exp
LOG_LEVEL=INFO
EOF
```

**Verify:**
```bash
cat {{HOME}}/vertexai-openai-proxy/config.env
```

**Expected:** File contains all variables with values substituted

### Step 4.5: Test Proxy Manually

**Command:**
```bash
cd {{HOME}}/vertexai-openai-proxy
source config.env
python3 app.py
```

**Expected:** Server starts, shows "Running on http://0.0.0.0:8000"

**Verify in new terminal:**
```bash
curl http://localhost:8000/v1/models
```

**Expected:** JSON response with available models list

**Stop the test:** Press Ctrl+C in the proxy terminal

⚠️ **GOTCHA:** After ANY code changes to the proxy, you MUST restart the service. Updated code ≠ deployed code. Always verify the process start time matches your code update time when debugging.

---

## Phase 5: Docker Sandbox Build

> Goal: Build secure Docker sandbox image for agent isolation

### Step 5.1: Create Dockerfile

**Command:**
```bash
cd {{HOME}}/openclaw
cat > Dockerfile.sandbox << 'EOF'
FROM node:20-alpine

# Security: Drop all capabilities, read-only root
RUN addgroup -g 1000 sandbox && \
    adduser -D -u 1000 -G sandbox sandbox

# Install minimal required tools
RUN apk add --no-cache \
    git \
    curl \
    bash

# Create workspace directory
RUN mkdir -p /workspace && chown sandbox:sandbox /workspace

USER sandbox
WORKDIR /workspace

CMD ["/bin/bash"]
EOF
```

**Verify:**
```bash
cat Dockerfile.sandbox
```

**Expected:** File contains the Dockerfile content

### Step 5.2: Build Sandbox Image

**Command:**
```bash
cd {{HOME}}/openclaw
docker build -t openclaw-sandbox:latest -f Dockerfile.sandbox .
```

**Expected:** Build completes with "Successfully tagged openclaw-sandbox:latest"

**Verify:**
```bash
docker images | grep openclaw-sandbox
```

**Expected:** Shows `openclaw-sandbox` with `latest` tag

### Step 5.3: Test Sandbox Security

**Command:**
```bash
docker run --rm openclaw-sandbox:latest whoami
```

**Expected:** Shows `sandbox` (not root)

**Test read-only filesystem:**
```bash
docker run --rm --read-only openclaw-sandbox:latest touch /test.txt
```

**Expected:** Fails with "Read-only file system" error (this is correct!)

⚠️ **GOTCHA:** The sandbox runs with read-only root and ALL capabilities dropped. Agents cannot modify system files, install packages, or access privileged operations. This is intentional for security.

---

## Phase 6: OpenClaw Configuration

> Goal: Configure OpenClaw to use Vertex AI proxy and Docker sandboxing

### Step 6.1: Create OpenClaw Config File

**Command:**
```bash
cat > {{HOME}}/.openclaw/config.json << 'EOF'
{
  "llm": {
    "provider": "openai",
    "baseURL": "http://localhost:8000/v1",
    "apiKey": "unused",
    "model": "gemini-2.0-flash-exp",
    "streaming": true,
    "temperature": 0.7,
    "maxTokens": 8192
  },
  "sandbox": {
    "enabled": true,
    "type": "docker",
    "image": "openclaw-sandbox:latest",
    "network": "bridge",
    "readOnlyRoot": true,
    "capabilities": []
  },
  "workspace": {
    "path": "{{HOME}}/.openclaw/workspace",
    "sandboxPath": "{{HOME}}/.openclaw/sandboxes"
  },
  "logging": {
    "level": "info",
    "file": "{{HOME}}/.openclaw/logs/openclaw.log"
  }
}
EOF
```

**Verify:**
```bash
cat {{HOME}}/.openclaw/config.json | grep "baseURL"
```

**Expected:** Shows `"baseURL": "http://localhost:8000/v1"`

⚠️ **GOTCHA:** The `streaming` flag MUST be `true` because OpenClaw hardcodes `stream: true` in all requests. If this is false, requests will fail.

### Step 6.2: Validate Configuration

**Command:**
```bash
cd {{HOME}}/openclaw
npm run validate-config
```

**Expected:** "Configuration valid" or similar success message

**If validation fails:** Check JSON syntax in config.json (trailing commas, quotes, brackets)

### Step 6.3: Test OpenClaw Connection

**Command:**
```bash
# Start proxy in background (if not already running)
cd {{HOME}}/vertexai-openai-proxy
source config.env
nohup python3 app.py > {{HOME}}/.openclaw/logs/proxy.log 2>&1 &
echo $! > {{HOME}}/.openclaw/proxy.pid

# Test OpenClaw
cd {{HOME}}/openclaw
npm run test-connection
```

**Expected:** Successfully connects to proxy and receives response

**If it fails:**
```bash
# Check proxy is running
curl http://localhost:8000/v1/models

# Check proxy logs
tail -f {{HOME}}/.openclaw/logs/proxy.log
```

---

## Phase 7: Slack Integration

> Goal: Configure Slack bot for notifications and interactions

### Step 7.1: Create Slack App

**Manual Step:**
1. Go to https://api.slack.com/apps
2. Click "Create New App" → "From scratch"
3. Name: "OpenClaw"
4. Select your workspace
5. Click "Create App"

### Step 7.2: Configure Bot Scopes

**Manual Step:**
1. In Slack App settings, go to "OAuth & Permissions"
2. Scroll to "Scopes" → "Bot Token Scopes"
3. Add these scopes:
   - `chat:write`
   - `channels:read`
   - `channels:history`
   - `groups:read`
   - `groups:history`
   - `im:read`
   - `im:history`
   - `im:write`
   - `users:read`
   - `files:write`

### Step 7.3: Enable Socket Mode

**Manual Step:**
1. In Slack App settings, go to "Socket Mode"
2. Enable Socket Mode
3. Create app-level token with scope `connections:write`
4. Save the token (starts with `xapp-`)

### Step 7.4: Install App to Workspace

**Manual Step:**
1. Go to "OAuth & Permissions"
2. Click "Install to Workspace"
3. Authorize the app
4. Copy the "Bot User OAuth Token" (starts with `xoxb-`)

### Step 7.5: Get Signing Secret

**Manual Step:**
1. Go to "Basic Information"
2. Scroll to "App Credentials"
3. Copy "Signing Secret"

### Step 7.6: Store Slack Credentials

**Command:**
```bash
cat > {{HOME}}/.openclaw/slack.env << 'EOF'
SLACK_BOT_TOKEN={{SLACK_BOT_TOKEN}}
SLACK_APP_TOKEN={{SLACK_APP_TOKEN}}
SLACK_SIGNING_SECRET={{SLACK_SIGNING_SECRET}}
EOF

chmod 600 {{HOME}}/.openclaw/slack.env
```

**Verify:**
```bash
cat {{HOME}}/.openclaw/slack.env
```

**Expected:** Shows all three variables with actual token values

⚠️ **SECURITY:** This file contains secrets. Ensure permissions are 600 (only you can read).

### Step 7.7: Update OpenClaw Config with Slack

**Command:**
```bash
cd {{HOME}}/openclaw
source {{HOME}}/.openclaw/slack.env

# Add Slack config to existing config.json
cat > {{HOME}}/.openclaw/config.json << EOF
{
  "llm": {
    "provider": "openai",
    "baseURL": "http://localhost:8000/v1",
    "apiKey": "unused",
    "model": "gemini-2.0-flash-exp",
    "streaming": true,
    "temperature": 0.7,
    "maxTokens": 8192
  },
  "sandbox": {
    "enabled": true,
    "type": "docker",
    "image": "openclaw-sandbox:latest",
    "network": "bridge",
    "readOnlyRoot": true,
    "capabilities": []
  },
  "workspace": {
    "path": "{{HOME}}/.openclaw/workspace",
    "sandboxPath": "{{HOME}}/.openclaw/sandboxes"
  },
  "logging": {
    "level": "info",
    "file": "{{HOME}}/.openclaw/logs/openclaw.log"
  },
  "slack": {
    "enabled": true,
    "botToken": "${SLACK_BOT_TOKEN}",
    "appToken": "${SLACK_APP_TOKEN}",
    "signingSecret": "${SLACK_SIGNING_SECRET}"
  }
}
EOF
```

**Verify:**
```bash
grep "slack" {{HOME}}/.openclaw/config.json
```

**Expected:** Shows Slack configuration block with token values

---

## Phase 8: Workspace Files Setup

> Goal: Create system configuration files for OpenClaw agents

⚠️ **CRITICAL:** Two separate workspace locations exist:
1. **Main workspace**: `{{HOME}}/.openclaw/workspace/` - System config files (SOUL.md, AGENTS.md, TOOLS.md)
2. **Sandbox workspace**: `{{HOME}}/.openclaw/sandboxes/agent-main-XXXXXXXX/` - Where agents read/write

Files do NOT auto-sync between workspaces. Agent-specific files must go in sandbox workspace.

### Step 8.1: Create SOUL.md (Main Workspace)

**Command:**
```bash
cat > {{HOME}}/.openclaw/workspace/SOUL.md << 'EOF'
# OpenClaw System Personality

You are OpenClaw, a multi-agent autonomous system designed to manage projects, execute tasks, and coordinate specialized agents.

## Core Principles
1. Safety first - never execute destructive commands without confirmation
2. Clarity - always explain what you're doing and why
3. Efficiency - use the right agent for each task
4. Verification - test and validate all changes

## Communication Style
- Concise and technical
- Show key changes, not every detail
- Flag risks before taking action
- Summarize: what changed, what was tested, next steps

## Error Handling
- If stuck after 2 attempts, stop and ask for help
- Always read error messages carefully
- Check logs before assuming API failures
EOF
```

### Step 8.2: Create AGENTS.md (Main Workspace)

**Command:**
```bash
cat > {{HOME}}/.openclaw/workspace/AGENTS.md << 'EOF'
# OpenClaw Agent Definitions

## Main Agent (Steve)
**Role:** Project manager and coordinator
**Capabilities:** Task delegation, progress tracking, user communication
**Skills:** heartbeat (proactive monitoring every 30min)
**Behavior:**
- Reads from sandbox workspace: {{HOME}}/.openclaw/sandboxes/agent-main-XXXXXXXX/
- Delegates specialized work to subagents
- Maintains HEARTBEAT.md for 24/7 monitoring

## Developer Agent
**Role:** Write and modify code
**Capabilities:** File editing, git operations, testing
**Skills:** fresh-eyes (MANDATORY after all code changes)
**Behavior:**
- Always run tests after code changes
- Follow existing code patterns
- Use fresh-eyes skill to review own work

## QA Agent
**Role:** Test and verify code quality
**Capabilities:** Test execution, bug detection, code review
**Skills:** peer-review (review other agents' work)
**Behavior:**
- Write tests before fixing bugs
- Verify all test pass before marking complete
- Check for security issues and edge cases

## Planner Agent
**Role:** Design and architecture
**Capabilities:** System design, research, planning
**Skills:** idea-wizard, plan-review
**Behavior:**
- Research before implementing
- Use idea-wizard for brainstorming (30 ideas → top 5)
- Use plan-review to validate plans with fresh eyes
EOF
```

### Step 8.3: Create TOOLS.md (Main Workspace)

**Command:**
```bash
cat > {{HOME}}/.openclaw/workspace/TOOLS.md << 'EOF'
# OpenClaw Tool Configuration

## Available Tools
1. **Bash** - Execute shell commands (with safety limits)
2. **Read** - Read file contents
3. **Write** - Write files (requires Read first for existing files)
4. **Edit** - Precise string replacements in files
5. **Glob** - File pattern matching
6. **Grep** - Content search across files
7. **WebFetch** - Fetch and analyze web content
8. **WebSearch** - Search the web for information

## Tool Usage Guidelines
- Always use Read before Write for existing files
- Prefer Edit over Write for small changes
- Use Glob for finding files, Grep for finding content
- Never use Bash for file operations (use dedicated tools)
- Always verify commands before execution

## Restricted Operations
- No force push to main/master
- No git config modifications
- No destructive operations without explicit confirmation
- No skipping git hooks (--no-verify)
EOF
```

### Step 8.4: Find Sandbox Workspace Directory

**Command:**
```bash
ls -la {{HOME}}/.openclaw/sandboxes/
```

**Expected:** Shows agent directory like `agent-main-0d71ad7a/`

**Note the exact directory name for next steps.** We'll use `{{SANDBOX_ID}}` as placeholder.

### Step 8.5: Create USER.md (Sandbox Workspace)

**Command:**
```bash
cat > {{HOME}}/.openclaw/sandboxes/{{SANDBOX_ID}}/USER.md << 'EOF'
# User Profile

**Name:** {{YOUR_NAME}}
**Role:** {{YOUR_ROLE}}

## Active Projects
1. **{{PROJECT_1}}** - Description and priority
2. **{{PROJECT_2}}** - Description and priority

## Working Style
- Preference for test-driven development
- Code review required for significant changes
- Ship fast, iterate on side projects

## Communication Preferences
- Concise and direct
- Flag risks proactively
- Summarize outcomes clearly
EOF
```

### Step 8.6: Create HEARTBEAT.md (Sandbox Workspace)

**Command:**
```bash
cat > {{HOME}}/.openclaw/sandboxes/{{SANDBOX_ID}}/HEARTBEAT.md << 'EOF'
# Heartbeat - Proactive 24/7 Management

Run this every 30 minutes to check system health and take proactive actions.

## Health Checks
1. **Vertex AI Proxy Status**
   - Check if proxy is running: `curl http://localhost:8000/v1/models`
   - If down, check logs: `tail -50 {{HOME}}/.openclaw/logs/proxy.log`
   - If needed, restart: Follow Phase 9 service restart steps

2. **OpenClaw Service Status**
   - Check process: `ps aux | grep openclaw`
   - Check logs: `tail -50 {{HOME}}/.openclaw/logs/openclaw.log`
   - Look for errors or stuck processes

3. **Disk Space**
   - Check usage: `df -h {{HOME}}/.openclaw`
   - Clean old logs if >1GB: `find {{HOME}}/.openclaw/logs -mtime +7 -delete`

4. **Docker Containers**
   - List running: `docker ps`
   - Clean stopped: `docker container prune -f`

## Proactive Actions
- If errors in logs, investigate and fix if trivial
- If service down, attempt restart
- If disk space low, clean old logs
- If repeated failures, notify user with details

## Cost Estimate
~$0.65/day with Gemini 2.5 Flash (135K input tokens per run, 48 runs/day)

## Output Format
```
[TIMESTAMP] Heartbeat Check
✓ Proxy: Running, {{N}} models available
✓ OpenClaw: Healthy, last activity {{TIME}}
✓ Disk: {{N}}% used
✓ Docker: {{N}} containers running
Actions taken: [None | Description]
```
EOF
```

⚠️ **GOTCHA:** Files in main workspace (`{{HOME}}/.openclaw/workspace/`) do NOT automatically sync to sandbox workspace. If agents need custom files, place them in sandbox workspace (`{{HOME}}/.openclaw/sandboxes/{{SANDBOX_ID}}/`).

---

## Phase 9: Service Setup (macOS LaunchD)

> Goal: Configure automatic startup for Vertex AI Proxy and OpenClaw

### Step 9.1: Create Proxy LaunchD Plist

**Command:**
```bash
cat > {{HOME}}/Library/LaunchAgents/com.openclaw.vertexai-proxy.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.vertexai-proxy</string>

    <key>ProgramArguments</key>
    <array>
        <string>{{HOME}}/vertexai-openai-proxy/venv/bin/python3</string>
        <string>{{HOME}}/vertexai-openai-proxy/app.py</string>
    </array>

    <key>WorkingDirectory</key>
    <string>{{HOME}}/vertexai-openai-proxy</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
        <key>PORT</key>
        <string>8000</string>
        <key>GCP_PROJECT_ID</key>
        <string>{{GCP_PROJECT_ID}}</string>
        <key>GCP_REGION</key>
        <string>{{GCP_REGION}}</string>
        <key>DEFAULT_MODEL</key>
        <string>gemini-2.0-flash-exp</string>
        <key>LOG_LEVEL</key>
        <string>INFO</string>
    </dict>

    <key>StandardOutPath</key>
    <string>{{HOME}}/.openclaw/logs/proxy.log</string>

    <key>StandardErrorPath</key>
    <string>{{HOME}}/.openclaw/logs/proxy.error.log</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
```

⚠️ **GOTCHA:** LaunchD services don't inherit shell PATH. Must explicitly set PATH to include `/usr/local/bin` (where gcloud is installed) and `/opt/homebrew/bin` (for Apple Silicon Macs). Without this, `gcloud` won't be found and authentication will fail.

### Step 9.2: Create OpenClaw LaunchD Plist

**Command:**
```bash
cat > {{HOME}}/Library/LaunchAgents/com.openclaw.main.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.main</string>

    <key>ProgramArguments</key>
    <array>
        <string>{{HOME}}/openclaw/node_modules/.bin/openclaw</string>
        <string>start</string>
    </array>

    <key>WorkingDirectory</key>
    <string>{{HOME}}/openclaw</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
        <key>NODE_ENV</key>
        <string>production</string>
    </dict>

    <key>StandardOutPath</key>
    <string>{{HOME}}/.openclaw/logs/openclaw.log</string>

    <key>StandardErrorPath</key>
    <string>{{HOME}}/.openclaw/logs/openclaw.error.log</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
```

### Step 9.3: Load Proxy Service

**Command:**
```bash
launchctl load {{HOME}}/Library/LaunchAgents/com.openclaw.vertexai-proxy.plist
```

**Verify:**
```bash
launchctl list | grep vertexai-proxy
```

**Expected:** Shows service with PID (not "-" or "0")

**Check logs:**
```bash
tail -20 {{HOME}}/.openclaw/logs/proxy.log
```

**Expected:** "Running on http://0.0.0.0:8000" message

### Step 9.4: Load OpenClaw Service

**Command:**
```bash
launchctl load {{HOME}}/Library/LaunchAgents/com.openclaw.main.plist
```

**Verify:**
```bash
launchctl list | grep openclaw.main
```

**Expected:** Shows service with PID

**Check logs:**
```bash
tail -20 {{HOME}}/.openclaw/logs/openclaw.log
```

**Expected:** OpenClaw startup messages, no errors

### Step 9.5: Service Management Commands

**Restart proxy after code changes (CRITICAL):**
```bash
launchctl unload {{HOME}}/Library/LaunchAgents/com.openclaw.vertexai-proxy.plist
launchctl load {{HOME}}/Library/LaunchAgents/com.openclaw.vertexai-proxy.plist
```

**Restart OpenClaw:**
```bash
launchctl unload {{HOME}}/Library/LaunchAgents/com.openclaw.main.plist
launchctl load {{HOME}}/Library/LaunchAgents/com.openclaw.main.plist
```

**Stop services:**
```bash
launchctl unload {{HOME}}/Library/LaunchAgents/com.openclaw.vertexai-proxy.plist
launchctl unload {{HOME}}/Library/LaunchAgents/com.openclaw.main.plist
```

⚠️ **GOTCHA:** ALWAYS restart services after code changes. Updated code ≠ deployed code. The service continues running the old code until restarted. Verify deployment by checking process start time matches code update time.

---

## Phase 9 Alternative: Service Setup (Windows NSSM)

> Goal: Configure automatic startup on Windows using NSSM

### Step 9W.1: Install NSSM

**Command (PowerShell as Administrator):**
```powershell
# Using Chocolatey
choco install nssm

# Or download from https://nssm.cc/download
```

**Verify:**
```powershell
nssm --version
```

**Expected:** NSSM version displayed

### Step 9W.2: Install Proxy Service

**Command (PowerShell as Administrator):**
```powershell
nssm install OpenClawProxy "{{HOME}}\vertexai-openai-proxy\venv\Scripts\python.exe" "{{HOME}}\vertexai-openai-proxy\app.py"

nssm set OpenClawProxy AppDirectory "{{HOME}}\vertexai-openai-proxy"
nssm set OpenClawProxy AppEnvironmentExtra "PORT=8000" "GCP_PROJECT_ID={{GCP_PROJECT_ID}}" "GCP_REGION={{GCP_REGION}}"
nssm set OpenClawProxy AppStdout "{{HOME}}\.openclaw\logs\proxy.log"
nssm set OpenClawProxy AppStderr "{{HOME}}\.openclaw\logs\proxy.error.log"

nssm start OpenClawProxy
```

### Step 9W.3: Install OpenClaw Service

**Command (PowerShell as Administrator):**
```powershell
nssm install OpenClaw "{{HOME}}\openclaw\node_modules\.bin\openclaw.cmd" "start"

nssm set OpenClaw AppDirectory "{{HOME}}\openclaw"
nssm set OpenClaw AppStdout "{{HOME}}\.openclaw\logs\openclaw.log"
nssm set OpenClaw AppStderr "{{HOME}}\.openclaw\logs\openclaw.error.log"

nssm start OpenClaw
```

### Step 9W.4: Service Management

**Restart services after code changes:**
```powershell
nssm restart OpenClawProxy
nssm restart OpenClaw
```

**Stop services:**
```powershell
nssm stop OpenClawProxy
nssm stop OpenClaw
```

**Remove services:**
```powershell
nssm remove OpenClawProxy confirm
nssm remove OpenClaw confirm
```

---

## Phase 10: Verification

> Goal: Confirm entire system is working end-to-end

### Step 10.1: Verify Proxy Health

**Command:**
```bash
curl http://localhost:8000/v1/models
```

**Expected:** JSON response with list of Vertex AI models

**If it fails:**
```bash
# Check proxy logs
tail -50 {{HOME}}/.openclaw/logs/proxy.log

# Check proxy is running
ps aux | grep "python3 app.py"

# Check gcloud authentication
gcloud auth application-default print-access-token
```

### Step 10.2: Test Streaming Endpoint

**Command:**
```bash
curl -N -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini-2.0-flash-exp",
    "messages": [{"role": "user", "content": "Say hello"}],
    "stream": true
  }'
```

**Expected:** SSE-formatted streaming response with data chunks

**If it fails:** Proxy doesn't support streaming (missing streaming code). You need the version with commit 18f2bde or later.

### Step 10.3: Verify OpenClaw Connection

**Command:**
```bash
cd {{HOME}}/openclaw
npm run health-check
```

**Expected:** All systems operational, connected to proxy

### Step 10.4: Test Agent Execution

**Command:**
```bash
cd {{HOME}}/openclaw
npm run test-agent -- --agent developer --task "List files in workspace"
```

**Expected:** Agent responds with file listing, no errors

### Step 10.5: Verify Slack Integration

**Manual Test:**
1. Open Slack workspace where OpenClaw is installed
2. Send DM to @OpenClaw bot: "Hello"
3. Should receive response

**If it fails:**
```bash
# Check Slack config
grep "slack" {{HOME}}/.openclaw/config.json

# Check OpenClaw logs for Slack errors
grep -i "slack" {{HOME}}/.openclaw/logs/openclaw.log
```

### Step 10.6: Verify Sandbox Security

**Command:**
```bash
cd {{HOME}}/openclaw
npm run test-agent -- --agent developer --task "Try to write to /etc/hosts"
```

**Expected:** Fails with "Read-only file system" or permission denied (this is correct!)

### Step 10.7: Verify Workspace Files

**Command:**
```bash
ls -la {{HOME}}/.openclaw/workspace/ | grep -E "SOUL|AGENTS|TOOLS"
ls -la {{HOME}}/.openclaw/sandboxes/{{SANDBOX_ID}}/ | grep -E "USER|HEARTBEAT"
```

**Expected:**
- Main workspace: SOUL.md, AGENTS.md, TOOLS.md
- Sandbox workspace: USER.md, HEARTBEAT.md

### Step 10.8: Test Heartbeat Monitoring

**Command:**
```bash
cd {{HOME}}/openclaw
npm run test-agent -- --agent main --skill heartbeat
```

**Expected:** Heartbeat runs all health checks, reports system status

**Verify cost estimate:**
- ~135K input tokens per heartbeat
- ~48 runs per day (every 30 min)
- ~$0.65/day with Gemini 2.5 Flash

---

## Phase 11: Optional - Custom Skills

> Goal: Add reusable prompt skills for specialized workflows

### Step 11.1: Create Skills Directory

**Command:**
```bash
mkdir -p {{HOME}}/.openclaw/workspace/skills
```

### Step 11.2: Add Fresh Eyes Skill

**Command:**
```bash
cat > {{HOME}}/.openclaw/workspace/skills/fresh-eyes.md << 'EOF'
# Fresh Eyes - Code Review Skill

After writing or modifying code, re-read ALL new/changed code with "fresh eyes" looking for:

1. **Obvious bugs and errors**
   - Logic errors
   - Off-by-one errors
   - Null pointer issues
   - Race conditions

2. **Bad assumptions**
   - Incorrect type assumptions
   - Missing input validation
   - Unhandled edge cases
   - API contract violations

3. **Inconsistencies**
   - Violates existing patterns
   - Different style from codebase
   - Duplicate logic that could be shared
   - Dead code or commented code

Fix anything found before moving on. Do this automatically — don't wait to be asked.

**MANDATORY for Developer Agent after ALL code changes.**
EOF
```

### Step 11.3: Add Bug Hunt Skill

**Command:**
```bash
cat > {{HOME}}/.openclaw/workspace/skills/bug-hunt.md << 'EOF'
# Bug Hunt - Proactive Bug Detection

Randomly explore the codebase looking for bugs through:

1. **Random Code Inspection**
   - Pick 3-5 files at random
   - Read through looking for obvious issues
   - Focus on error handling and edge cases

2. **Execution Flow Tracing**
   - Pick a feature entry point
   - Trace execution through entire flow
   - Look for paths that could fail
   - Verify error handling exists

3. **Common Vulnerability Patterns**
   - SQL injection risks
   - XSS vulnerabilities
   - Missing authentication checks
   - Exposed secrets in code

Document any issues found with:
- File and line number
- Description of the issue
- Potential impact
- Suggested fix
EOF
```

### Step 11.4: Add Idea Wizard Skill

**Command:**
```bash
cat > {{HOME}}/.openclaw/workspace/skills/idea-wizard.md << 'EOF'
# Idea Wizard - Brainstorming Framework

Generate and evaluate ideas systematically:

## Phase 1: Generate 30 Ideas
- Spend 10 minutes brainstorming
- No filtering, all ideas welcome
- Focus on quantity over quality
- Write brief one-line descriptions

## Phase 2: Evaluate Each Idea
For each idea, score 1-5 on:
- **Feasibility**: Can we actually build this?
- **Impact**: How much value does it provide?
- **Novelty**: Is it different from existing solutions?

## Phase 3: Select Top 5
- Sort by total score
- Eliminate obvious non-starters
- Pick top 5 for detailed analysis

## Phase 4: Detailed Analysis
For each top 5 idea:
- Full description (2-3 paragraphs)
- Technical approach
- Estimated effort
- Potential risks
- Expected outcomes

**Use for: Project planning, feature design, architecture decisions**
EOF
```

### Step 11.5: Add Plan Review Skill

**Command:**
```bash
cat > {{HOME}}/.openclaw/workspace/skills/plan-review.md << 'EOF'
# Plan Review - Multi-Pass Validation

Review plans with fresh eyes, looking for:

## Pass 1: Conceptual Errors
- Logical violations
- Impossible requirements
- Conflicting goals
- Misunderstood requirements

## Pass 2: Bad Assumptions
- Assuming services exist that don't
- Assuming APIs work in specific ways without checking
- Assuming user behavior
- Assuming system capabilities

## Pass 3: Missing Steps
- Skipped dependencies
- Missing error handling
- No rollback plan
- No testing strategy

## Pass 4: Sloppy Thinking
- Vague descriptions
- Ambiguous success criteria
- No timeline estimates
- Missing acceptance criteria

Revise the plan in-place before presenting. Repeat until "steady state" (no more changes).

**MANDATORY for Planner Agent before presenting plans.**
EOF
```

### Step 11.6: Add Peer Review Skill

**Command:**
```bash
cat > {{HOME}}/.openclaw/workspace/skills/peer-review.md << 'EOF'
# Peer Review - Cross-Agent Code Review

Review another agent's work comprehensively:

## Code Quality
- Follows existing patterns?
- Clear and readable?
- Proper error handling?
- No commented-out code?

## Testing
- Tests exist for changes?
- Tests actually test the right thing?
- Edge cases covered?
- Tests pass?

## Security
- Input validation present?
- Authentication checked?
- Authorization verified?
- No exposed secrets?

## Performance
- Efficient algorithms used?
- No N+1 queries?
- Proper caching where needed?
- Scalability concerns addressed?

## Documentation
- Code comments where needed?
- API documentation updated?
- README updated if needed?

Provide specific feedback with file/line references.

**Use for: QA Agent reviewing Developer Agent's work**
EOF
```

### Step 11.7: Update AGENTS.md with Skill References

**Command:**
```bash
# Verify skills are documented in AGENTS.md (already done in Step 8.2)
grep -A 2 "Skills:" {{HOME}}/.openclaw/workspace/AGENTS.md
```

**Expected:** Each agent shows their mandatory/recommended skills

---

## Phase 12: Optional - 1Password Integration

> Goal: Secure credential management using 1Password service accounts

### Step 12.1: Create 1Password Service Account

**Manual Step:**
1. Log into 1Password
2. Go to Settings → Service Accounts
3. Create new service account named "OpenClaw"
4. Grant read access to required vaults
5. Copy the service account token

### Step 12.2: Store 1Password Token

**Command:**
```bash
cat > {{HOME}}/.openclaw/1password.env << 'EOF'
OP_SERVICE_ACCOUNT_TOKEN={{ONEPASSWORD_SERVICE_ACCOUNT_TOKEN}}
EOF

chmod 600 {{HOME}}/.openclaw/1password.env
```

### Step 12.3: Install 1Password CLI

**Command:**
```bash
# macOS
brew install --cask 1password-cli

# Linux
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
  sudo tee /etc/apt/sources.list.d/1password.list
sudo apt update && sudo apt install 1password-cli

# Windows
# Download from https://1password.com/downloads/command-line/
```

**Verify:**
```bash
op --version
```

**Expected:** 1Password CLI version displayed

### Step 12.4: Test 1Password Integration

**Command:**
```bash
source {{HOME}}/.openclaw/1password.env
op vault list
```

**Expected:** List of accessible vaults displayed

### Step 12.5: Create Helper Script for Credentials

**Command:**
```bash
cat > {{HOME}}/.openclaw/bin/get-credential.sh << 'EOF'
#!/bin/bash
# Usage: get-credential.sh <item-name> <field-name>

source {{HOME}}/.openclaw/1password.env
op item get "$1" --fields "$2" --reveal
EOF

chmod +x {{HOME}}/.openclaw/bin/get-credential.sh
```

**Test:**
```bash
{{HOME}}/.openclaw/bin/get-credential.sh "Slack OpenClaw" "bot_token"
```

**Expected:** Returns Slack bot token

### Step 12.6: Update Service Plists to Use 1Password

**Example for Proxy (macOS):**
```bash
# Modify proxy plist to source credentials from 1Password
cat > {{HOME}}/Library/LaunchAgents/com.openclaw.vertexai-proxy.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.vertexai-proxy</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>source {{HOME}}/.openclaw/1password.env && exec {{HOME}}/vertexai-openai-proxy/venv/bin/python3 {{HOME}}/vertexai-openai-proxy/app.py</string>
    </array>

    <key>WorkingDirectory</key>
    <string>{{HOME}}/vertexai-openai-proxy</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
        <key>PORT</key>
        <string>8000</string>
        <key>GCP_PROJECT_ID</key>
        <string>{{GCP_PROJECT_ID}}</string>
        <key>GCP_REGION</key>
        <string>{{GCP_REGION}}</string>
    </dict>

    <key>StandardOutPath</key>
    <string>{{HOME}}/.openclaw/logs/proxy.log</string>

    <key>StandardErrorPath</key>
    <string>{{HOME}}/.openclaw/logs/proxy.error.log</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
```

**Reload service:**
```bash
launchctl unload {{HOME}}/Library/LaunchAgents/com.openclaw.vertexai-proxy.plist
launchctl load {{HOME}}/Library/LaunchAgents/com.openclaw.vertexai-proxy.plist
```

---

## Troubleshooting Guide

### Proxy Won't Start

**Symptoms:** Proxy logs show "Permission denied" or "Module not found"

**Check:**
```bash
# Verify virtual environment
ls -la {{HOME}}/vertexai-openai-proxy/venv/bin/python3

# Verify dependencies installed
{{HOME}}/vertexai-openai-proxy/venv/bin/python3 -c "import vertexai"

# Check authentication
unset GOOGLE_APPLICATION_CREDENTIALS
gcloud auth application-default print-access-token
```

**Fix:**
```bash
cd {{HOME}}/vertexai-openai-proxy
source venv/bin/activate
pip install -r requirements.txt
```

### Streaming Requests Fail

**Symptoms:** OpenClaw gets "Invalid response" errors

**Check:**
```bash
grep "client.stream()" {{HOME}}/vertexai-openai-proxy/app.py
```

**Fix:** You need proxy version with streaming support (commit 18f2bde). Clone the correct version or add streaming code.

### Sandbox Cannot Write Files

**Symptoms:** Agent tasks fail with "Read-only file system"

**This is correct!** Sandbox runs read-only for security. Agents should write to mounted workspace volumes only.

**Check Docker run command:**
```bash
docker inspect openclaw-sandbox:latest | grep -A 5 "ReadonlyRootfs"
```

**Expected:** `"ReadonlyRootfs": true`

### Service Keeps Using Old Code

**Symptoms:** Made code changes, but behavior doesn't change

**Cause:** Service not restarted after code changes

**Fix:**
```bash
# macOS
launchctl unload {{HOME}}/Library/LaunchAgents/com.openclaw.vertexai-proxy.plist
launchctl load {{HOME}}/Library/LaunchAgents/com.openclaw.vertexai-proxy.plist

# Windows
nssm restart OpenClawProxy
```

**Verify deployment:**
```bash
# Check process start time
ps aux | grep "app.py" | grep -v grep

# Should show start time AFTER your code changes
```

### gcloud Command Not Found

**Symptoms:** Proxy logs show "gcloud: command not found"

**Cause:** LaunchD PATH doesn't include gcloud location

**Fix:** Verify PATH in LaunchD plist includes:
- `/usr/local/bin` (Intel Mac)
- `/opt/homebrew/bin` (Apple Silicon Mac)

```bash
# Update plist PATH
cat {{HOME}}/Library/LaunchAgents/com.openclaw.vertexai-proxy.plist | grep PATH
```

**Should show:**
```xml
<key>PATH</key>
<string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
```

### Workspace Files Not Found

**Symptoms:** Agent can't read USER.md or HEARTBEAT.md

**Cause:** Files in wrong workspace location

**Check:**
```bash
# Main workspace (system config only)
ls -la {{HOME}}/.openclaw/workspace/

# Sandbox workspace (agent files)
ls -la {{HOME}}/.openclaw/sandboxes/*/
```

**Fix:** Move agent files to sandbox workspace:
```bash
SANDBOX_ID=$(ls {{HOME}}/.openclaw/sandboxes/ | head -1)
cp {{HOME}}/.openclaw/workspace/USER.md {{HOME}}/.openclaw/sandboxes/$SANDBOX_ID/
cp {{HOME}}/.openclaw/workspace/HEARTBEAT.md {{HOME}}/.openclaw/sandboxes/$SANDBOX_ID/
```

### High Token Usage / Costs

**Symptoms:** Daily costs higher than expected

**Check heartbeat frequency:**
```bash
grep -A 2 "Heartbeat" {{HOME}}/.openclaw/logs/openclaw.log | tail -20
```

**Expected:** ~30 minutes between runs

**Cost estimate:**
- 135K input tokens per heartbeat
- 48 runs/day (every 30 min)
- ~$0.65/day with Gemini 2.5 Flash

**Reduce costs:**
1. Increase heartbeat interval to 1 hour (24 runs/day = ~$0.32/day)
2. Reduce context in HEARTBEAT.md (fewer input tokens)
3. Use Gemini 2.5 Flash instead of Pro (lower per-token cost)

---

## Quick Reference

### Essential Commands

**Check system status:**
```bash
# Proxy health
curl http://localhost:8000/v1/models

# OpenClaw health
cd {{HOME}}/openclaw && npm run health-check

# View logs
tail -f {{HOME}}/.openclaw/logs/proxy.log
tail -f {{HOME}}/.openclaw/logs/openclaw.log
```

**Restart services (macOS):**
```bash
launchctl unload {{HOME}}/Library/LaunchAgents/com.openclaw.vertexai-proxy.plist
launchctl load {{HOME}}/Library/LaunchAgents/com.openclaw.vertexai-proxy.plist

launchctl unload {{HOME}}/Library/LaunchAgents/com.openclaw.main.plist
launchctl load {{HOME}}/Library/LaunchAgents/com.openclaw.main.plist
```

**Restart services (Windows):**
```powershell
nssm restart OpenClawProxy
nssm restart OpenClaw
```

**Check Docker sandbox:**
```bash
docker ps
docker images | grep openclaw-sandbox
```

**Clean Docker:**
```bash
docker container prune -f
docker image prune -f
```

### File Locations

- **OpenClaw config**: `{{HOME}}/.openclaw/config.json`
- **Proxy code**: `{{HOME}}/vertexai-openai-proxy/`
- **Main workspace**: `{{HOME}}/.openclaw/workspace/` (system config)
- **Sandbox workspace**: `{{HOME}}/.openclaw/sandboxes/{{SANDBOX_ID}}/` (agent files)
- **Logs**: `{{HOME}}/.openclaw/logs/`
- **Skills**: `{{HOME}}/.openclaw/workspace/skills/`
- **LaunchD plists**: `{{HOME}}/Library/LaunchAgents/`

### Important Gotchas Summary

1. **ALWAYS restart services after code changes** - Updated code ≠ deployed code
2. **LaunchD PATH must include gcloud location** - `/usr/local/bin` and `/opt/homebrew/bin`
3. **Proxy MUST support streaming** - OpenClaw hardcodes `stream: true`
4. **Use ADC, not service accounts** - `unset GOOGLE_APPLICATION_CREDENTIALS`
5. **Workspace files don't auto-sync** - Agent files go in sandbox workspace
6. **Sandbox is read-only** - This is intentional security, not a bug
7. **Verify deployment by process start time** - Check PID start time matches code changes

---

## Success Criteria

You've successfully completed setup when:

✅ Proxy responds to health checks with model list
✅ Streaming requests work (SSE format response)
✅ OpenClaw connects to proxy without errors
✅ Test agent can execute simple tasks
✅ Slack bot responds to DM messages
✅ Sandbox security prevents root filesystem writes
✅ Services start automatically on boot
✅ Heartbeat monitoring runs every 30 minutes
✅ All workspace files exist in correct locations
✅ Skills are available for agent use

**Next steps:**
1. Customize USER.md with your projects and preferences
2. Add project-specific context files to sandbox workspace
3. Create custom skills for repeated workflows
4. Configure notification preferences in Slack
5. Set up 1Password integration for secure credential management (optional)

---

## Support & Documentation

**OpenClaw GitHub**: https://github.com/cyanheads/openclaw
**Vertex AI Docs**: https://cloud.google.com/vertex-ai/docs
**LaunchD Reference**: `man launchd.plist`
**Docker Reference**: https://docs.docker.com/

**When asking for help, include:**
1. Output of `curl http://localhost:8000/v1/models`
2. Last 50 lines of `{{HOME}}/.openclaw/logs/proxy.log`
3. Last 50 lines of `{{HOME}}/.openclaw/logs/openclaw.log`
4. Output of `launchctl list | grep openclaw`
5. Output of `docker ps` and `docker images`

---

*Guide version: 1.0*
*Last updated: 2026-02-09*
*Compatible with: OpenClaw v1.x, Vertex AI Gemini models*
