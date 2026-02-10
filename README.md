# OpenClaw Setup Guide

A complete guide to setting up OpenClaw with Google Vertex AI, Docker sandboxing, and Slack integration for a powerful multi-agent AI system.

## What Is This?

OpenClaw is a multi-agent orchestration system that enables AI agents to work together autonomously. This guide walks you through connecting OpenClaw to Google's Vertex AI (using Gemini models) via a custom proxy, running agents in secure Docker containers, and integrating everything with Slack for 24/7 autonomous operation. The result is a system where specialized AI agents can collaborate, delegate tasks, and manage workflows continuously with minimal human intervention.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER INTERACTION                        │
│                    (Slack / CLI / API)                          │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                       OPENCLAW CORE                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Main Agent   │  │ Planner      │  │ QA Reviewer  │         │
│  │ (Steve)      │  │ Agent        │  │ Agent        │         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
│         │                 │                 │                  │
│         └─────────────────┼─────────────────┘                  │
│                           │                                     │
└───────────────────────────┼─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                   VERTEX AI PROXY (Python)                      │
│  - Translates OpenAI API → Vertex AI API                       │
│  - Handles authentication (gcloud ADC)                          │
│  - Streams responses via SSE                                    │
│  - Runs as LaunchD/NSSM service                                 │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GOOGLE VERTEX AI                             │
│  - Gemini 2.5 Flash (fast, cheap)                              │
│  - Gemini 2.5 Pro (reasoning)                                   │
│  - Pay-per-token pricing                                        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    DOCKER SANDBOX                               │
│  - Read-only root filesystem                                    │
│  - Dropped ALL capabilities                                     │
│  - Bridge network (no direct internet)                          │
│  - Volume-mounted workspace                                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   SLACK INTEGRATION                             │
│  - Heartbeat notifications every 30 min                         │
│  - Task updates and alerts                                      │
│  - Bi-directional communication                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Component Explanations

- **OpenClaw Core**: Orchestrates multiple AI agents, manages sessions, handles tool execution
- **Vertex AI Proxy**: Bridges OpenAI-compatible API calls to Google's Vertex AI, enabling use of Gemini models
- **Docker Sandbox**: Provides isolated, secure execution environment for agent operations
- **Slack Integration**: Enables asynchronous notifications and control via Slack workspace

> **📚 For detailed agent architecture**, including how agents delegate to external CLIs (Claude Code, Cursor) and the multi-tier model selection strategy, see [docs/AGENT_ARCHITECTURE.md](docs/AGENT_ARCHITECTURE.md).

## Prerequisites

Before starting, ensure you have:

### Required
- **Google Cloud Platform account** with billing enabled
- **Vertex AI API** enabled in your GCP project
- **Slack workspace** with admin permissions to create apps
- **Docker Desktop** installed and running
- **Node.js 20+** installed
- **Python 3.9+** installed
- **gcloud CLI** installed and configured
- **Git** for cloning repositories

### Optional but Recommended
- **1Password CLI** (`op`) for secure secrets management
- **jq** for JSON processing in scripts

### System Requirements
- macOS 11+ or Windows 10+ (with WSL2 for Docker)
- 8GB+ RAM recommended
- 10GB+ free disk space

## Quick Start

For automated installation, use one of these scripts:

### macOS
```bash
cd ~/openclaw-setup-guide
chmod +x setup-mac.sh
./setup-mac.sh
```

### Windows (PowerShell as Administrator)
```powershell
cd ~\openclaw-setup-guide
Set-ExecutionPolicy Bypass -Scope Process
.\setup-windows.ps1
```

The automated scripts will:
1. Install OpenClaw
2. Set up the Vertex AI proxy
3. Configure Docker sandboxing
4. Create service files (LaunchD/NSSM)
5. Guide you through manual steps (Slack app, GCP credentials)

**Note:** Even with automated scripts, you'll need to manually create the Slack app and configure GCP credentials.

## Manual Setup

Follow these steps for full manual installation and configuration.

### 5a. Install OpenClaw

```bash
# Clone the repository
git clone https://github.com/ckreiling/openclaw.git ~/.openclaw

# Install dependencies
cd ~/.openclaw
npm install

# Verify installation
npm start -- --help
```

You should see OpenClaw's help output.

### 5b. Google Cloud Setup

1. **Enable Vertex AI API**
   ```bash
   gcloud services enable aiplatform.googleapis.com
   ```

2. **Set up Application Default Credentials (ADC)**
   ```bash
   gcloud auth application-default login
   ```

   This creates credentials at `~/.config/gcloud/application_default_credentials.json`

3. **Verify your GCP project**
   ```bash
   gcloud config get-value project
   ```

   Note this project ID - you'll need it for the proxy configuration.

4. **Grant necessary permissions**

   Your user account needs these IAM roles:
   - `roles/aiplatform.user` (to call Vertex AI APIs)

   ```bash
   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="user:YOUR_EMAIL" \
     --role="roles/aiplatform.user"
   ```

### 5c. Vertex AI Proxy

1. **Clone the proxy repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/vertex-ai-proxy.git ~/vertex-ai-proxy
   cd ~/vertex-ai-proxy
   ```

2. **Install Python dependencies**
   ```bash
   python3 -m pip install -r requirements.txt
   ```

3. **Create configuration file**
   ```bash
   cp .env.example .env
   ```

   Edit `.env`:
   ```bash
   # Google Cloud Configuration
   PROJECT_ID=your-gcp-project-id
   LOCATION=us-central1

   # Server Configuration
   PORT=8000
   HOST=127.0.0.1

   # Authentication - LEAVE EMPTY for ADC
   # GOOGLE_APPLICATION_CREDENTIALS=

   # Model Configuration
   DEFAULT_MODEL=gemini-2.5-flash-preview-0205

   # Logging
   LOG_LEVEL=INFO
   ```

4. **Test the proxy manually**
   ```bash
   python3 proxy.py
   ```

   In another terminal:
   ```bash
   curl http://localhost:8000/v1/models
   ```

   You should see a list of available models.

5. **Important: Unset GOOGLE_APPLICATION_CREDENTIALS**

   If you have this environment variable set, unset it:
   ```bash
   unset GOOGLE_APPLICATION_CREDENTIALS
   ```

   The proxy must use ADC (Application Default Credentials) from gcloud, not a service account key file.

### 5d. Docker Sandbox

1. **Create Dockerfile**

   Save this as `~/vertex-ai-proxy/Dockerfile.sandbox`:
   ```dockerfile
   FROM node:20-slim

   # Install minimal dependencies
   RUN apt-get update && apt-get install -y \
       git \
       curl \
       && rm -rf /var/lib/apt/lists/*

   # Create non-root user
   RUN useradd -m -u 1000 sandbox

   # Set working directory
   WORKDIR /workspace

   # Switch to non-root user
   USER sandbox

   # Default command
   CMD ["/bin/bash"]
   ```

2. **Build the Docker image**
   ```bash
   docker build -f ~/vertex-ai-proxy/Dockerfile.sandbox \
     -t openclaw-sandbox:latest \
     ~/vertex-ai-proxy
   ```

3. **Verify the image**
   ```bash
   docker images | grep openclaw-sandbox
   ```

### 5e. OpenClaw Configuration

1. **Copy template files**
   ```bash
   cp ~/openclaw-setup-guide/templates/SOUL.md ~/.openclaw/workspace/SOUL.md
   cp ~/openclaw-setup-guide/templates/AGENTS.md ~/.openclaw/workspace/AGENTS.md
   cp ~/openclaw-setup-guide/templates/TOOLS.md ~/.openclaw/workspace/TOOLS.md
   cp ~/openclaw-setup-guide/templates/USER.md ~/.openclaw/sandboxes/agent-main-*/USER.md
   ```

2. **Edit SOUL.md**

   Update the model configuration:
   ```markdown
   ## Models

   Use Vertex AI models via the proxy:
   - Fast: gemini-2.5-flash-preview-0205
   - Reasoning: gemini-2.5-pro-preview-0215

   Proxy endpoint: http://localhost:8000/v1
   ```

3. **Edit AGENTS.md**

   Configure your agents (see template for full example):
   ```markdown
   ## Main Agent (Steve)

   Role: Autonomous project manager
   Model: gemini-2.5-flash-preview-0205
   Reasoning: low
   Tools: all
   ```

4. **Edit USER.md**

   Add your project context (this goes in the sandbox workspace):
   ```markdown
   # User Context

   Name: Your Name
   Projects: Your active projects
   Preferences: Your coding preferences
   ```

### 5f. Slack App Creation

1. **Go to https://api.slack.com/apps**

2. **Click "Create New App" > "From scratch"**
   - App Name: `OpenClaw`
   - Workspace: Select your workspace

3. **Configure OAuth Scopes**

   Under "OAuth & Permissions", add these Bot Token Scopes:

   **Required for basic functionality:**
   - `chat:write` - Send messages
   - `chat:write.public` - Send messages to public channels without joining
   - `channels:read` - View basic channel info
   - `groups:read` - View basic private channel info
   - `im:read` - View direct message info
   - `mpim:read` - View group direct message info

   **Optional but recommended:**
   - `channels:history` - Read message history
   - `groups:history` - Read private channel history
   - `im:history` - Read direct message history
   - `users:read` - View user info
   - `reactions:write` - Add emoji reactions

4. **Install to workspace**

   Click "Install to Workspace" and authorize.

5. **Copy tokens**

   - **Bot Token**: Found under "OAuth & Permissions" (starts with `xoxb-`)
   - **App Token**: Under "Basic Information" > "App-Level Tokens" (starts with `xapp-`)

   Save these securely - you'll need them for environment variables.

6. **Get Channel ID**

   In Slack:
   - Right-click the channel where you want notifications
   - Select "View channel details"
   - Scroll to bottom, copy the Channel ID

### 5g. Environment Variables

1. **Create .env file for OpenClaw**

   Save as `~/.openclaw/.env`:
   ```bash
   # Vertex AI Proxy
   OPENAI_API_BASE=http://localhost:8000/v1
   OPENAI_API_KEY=dummy-key-not-used

   # Slack Integration
   SLACK_BOT_TOKEN=xoxb-your-bot-token
   SLACK_APP_TOKEN=xapp-your-app-token
   SLACK_CHANNEL_ID=C01234567

   # Docker Configuration
   DOCKER_SANDBOX_IMAGE=openclaw-sandbox:latest
   DOCKER_SANDBOX_SECURITY_OPT=no-new-privileges:true
   DOCKER_SANDBOX_READ_ONLY=true
   DOCKER_SANDBOX_CAP_DROP=ALL

   # Agent Configuration
   DEFAULT_MODEL=gemini-2.5-flash-preview-0205
   REASONING_MODEL=gemini-2.5-pro-preview-0215
   ```

2. **Secure the .env file**
   ```bash
   chmod 600 ~/.openclaw/.env
   ```

3. **Optional: Use 1Password for secrets**

   If you have 1Password CLI:
   ```bash
   # Store tokens
   op item create --category=login \
     --title="OpenClaw Slack" \
     --field="bot_token=xoxb-your-token" \
     --field="app_token=xapp-your-token"

   # Reference in .env
   SLACK_BOT_TOKEN=op://Private/OpenClaw Slack/bot_token
   SLACK_APP_TOKEN=op://Private/OpenClaw Slack/app_token
   ```

### 5h. Workspace Files

1. **Create HEARTBEAT.md for Steve**

   Save as `~/.openclaw/sandboxes/agent-main-*/HEARTBEAT.md`:
   ```markdown
   # Heartbeat Protocol

   Every 30 minutes:
   1. Check project status
   2. Review pending tasks
   3. Send update to Slack
   4. Look for opportunities to help

   Format:
   - Status: [Active projects]
   - Tasks: [Pending items]
   - Blockers: [Issues needing attention]
   - Next: [Upcoming work]
   ```

2. **Create project context files**

   Example `~/.openclaw/sandboxes/agent-main-*/CALICO-CONTEXT.md`:
   ```markdown
   # Calico Spanish Project

   ## Overview
   Laravel membership platform for Spanish learning

   ## Tech Stack
   - Laravel 10
   - Filament admin
   - Stripe billing

   ## Current Focus
   License renewal email campaign
   ```

3. **Add custom skills (optional)**

   Copy Emanuel technique skills:
   ```bash
   cp ~/openclaw-setup-guide/skills/*.md ~/.openclaw/workspace/skills/
   ```

### 5i. Service Setup

Choose your operating system:

#### macOS (LaunchD)

1. **Create LaunchD plist for Vertex AI Proxy**

   Save as `~/Library/LaunchAgents/com.user.vertex-ai-proxy.plist`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Label</key>
       <string>com.user.vertex-ai-proxy</string>
       <key>ProgramArguments</key>
       <array>
           <string>/usr/local/bin/python3</string>
           <string>/Users/YOURUSERNAME/vertex-ai-proxy/proxy.py</string>
       </array>
       <key>WorkingDirectory</key>
       <string>/Users/YOURUSERNAME/vertex-ai-proxy</string>
       <key>StandardOutPath</key>
       <string>/Users/YOURUSERNAME/vertex-ai-proxy/logs/stdout.log</string>
       <key>StandardErrorPath</key>
       <string>/Users/YOURUSERNAME/vertex-ai-proxy/logs/stderr.log</string>
       <key>EnvironmentVariables</key>
       <dict>
           <key>PATH</key>
           <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
       </dict>
       <key>RunAtLoad</key>
       <true/>
       <key>KeepAlive</key>
       <true/>
   </dict>
   </plist>
   ```

   **Important:** Replace `YOURUSERNAME` with your actual username.

2. **Create log directory**
   ```bash
   mkdir -p ~/vertex-ai-proxy/logs
   ```

3. **Load the service**
   ```bash
   launchctl load ~/Library/LaunchAgents/com.user.vertex-ai-proxy.plist
   ```

4. **Verify it's running**
   ```bash
   launchctl list | grep vertex-ai-proxy
   curl http://localhost:8000/v1/models
   ```

5. **Create LaunchD plist for OpenClaw**

   Save as `~/Library/LaunchAgents/com.user.openclaw.plist`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Label</key>
       <string>com.user.openclaw</string>
       <key>ProgramArguments</key>
       <array>
           <string>/usr/local/bin/node</string>
           <string>/Users/YOURUSERNAME/.openclaw/index.js</string>
           <string>--agent</string>
           <string>main</string>
       </array>
       <key>WorkingDirectory</key>
       <string>/Users/YOURUSERNAME/.openclaw</string>
       <key>StandardOutPath</key>
       <string>/Users/YOURUSERNAME/.openclaw/logs/stdout.log</string>
       <key>StandardErrorPath</key>
       <string>/Users/YOURUSERNAME/.openclaw/logs/stderr.log</string>
       <key>RunAtLoad</key>
       <true/>
       <key>KeepAlive</key>
       <true/>
   </dict>
   </plist>
   ```

6. **Load OpenClaw service**
   ```bash
   mkdir -p ~/.openclaw/logs
   launchctl load ~/Library/LaunchAgents/com.user.openclaw.plist
   ```

#### Windows (NSSM)

1. **Install NSSM**
   ```powershell
   # Using Chocolatey
   choco install nssm

   # Or download from https://nssm.cc/download
   ```

2. **Install Vertex AI Proxy as service**
   ```powershell
   nssm install VertexAIProxy `
     "C:\Python39\python.exe" `
     "C:\Users\YOURUSERNAME\vertex-ai-proxy\proxy.py"

   nssm set VertexAIProxy AppDirectory "C:\Users\YOURUSERNAME\vertex-ai-proxy"
   nssm set VertexAIProxy AppStdout "C:\Users\YOURUSERNAME\vertex-ai-proxy\logs\stdout.log"
   nssm set VertexAIProxy AppStderr "C:\Users\YOURUSERNAME\vertex-ai-proxy\logs\stderr.log"
   nssm set VertexAIProxy Start SERVICE_AUTO_START

   nssm start VertexAIProxy
   ```

3. **Install OpenClaw as service**
   ```powershell
   nssm install OpenClaw `
     "C:\Program Files\nodejs\node.exe" `
     "C:\Users\YOURUSERNAME\.openclaw\index.js --agent main"

   nssm set OpenClaw AppDirectory "C:\Users\YOURUSERNAME\.openclaw"
   nssm set OpenClaw AppStdout "C:\Users\YOURUSERNAME\.openclaw\logs\stdout.log"
   nssm set OpenClaw AppStderr "C:\Users\YOURUSERNAME\.openclaw\logs\stderr.log"
   nssm set OpenClaw Start SERVICE_AUTO_START

   nssm start OpenClaw
   ```

4. **Verify services**
   ```powershell
   nssm status VertexAIProxy
   nssm status OpenClaw
   ```

### 5j. Verification Checklist

Run through this checklist to ensure everything is working:

- [ ] **Vertex AI Proxy responding**
  ```bash
  curl http://localhost:8000/v1/models
  ```
  Should return JSON list of models.

- [ ] **Docker sandbox working**
  ```bash
  docker run --rm openclaw-sandbox:latest echo "Hello"
  ```
  Should print "Hello".

- [ ] **OpenClaw can connect to proxy**
  ```bash
  cd ~/.openclaw
  npm start -- --test-connection
  ```

- [ ] **Slack bot is online**
  Check your Slack workspace - the bot should show as "Active".

- [ ] **Environment variables loaded**
  ```bash
  # macOS/Linux
  launchctl list | grep vertex-ai-proxy
  launchctl list | grep openclaw

  # Windows
  nssm status VertexAIProxy
  nssm status OpenClaw
  ```

- [ ] **Heartbeat working**
  Wait 30 minutes and check Slack for a heartbeat message from Steve.

- [ ] **Logs are clean**
  ```bash
  # Check for errors
  tail -f ~/vertex-ai-proxy/logs/stderr.log
  tail -f ~/.openclaw/logs/stderr.log
  ```

## Customization

### Modify Agent Behavior

Edit `~/.openclaw/workspace/AGENTS.md`:

```markdown
## Main Agent (Steve)

Role: Your custom role description
Model: gemini-2.5-flash-preview-0205
Reasoning: low | medium | high
Temperature: 0.7
MaxTokens: 4096
Tools: all | [specific tools]

Instructions:
- Custom instruction 1
- Custom instruction 2
```

**Reasoning levels:**
- `low`: Fast, cheaper, good for routine tasks
- `medium`: Balanced reasoning and speed
- `high`: Deep reasoning, slower, more expensive

### Add New Models

Edit `~/.openclaw/workspace/SOUL.md`:

```markdown
## Models

- gemini-2.5-flash-preview-0205 (fast, cheap)
- gemini-2.5-pro-preview-0215 (reasoning)
- claude-opus-4-6 (if using Anthropic proxy)
```

Update agent definitions to reference the new model.

### Adjust Heartbeat Frequency

Edit `~/.openclaw/sandboxes/agent-main-*/HEARTBEAT.md`:

```markdown
# Heartbeat Protocol

Every 60 minutes:  # Change from 30 to 60
...
```

### Add Custom Skills

Create a new `.md` file in `~/.openclaw/workspace/skills/`:

```markdown
# Custom Skill Name

## Purpose
What this skill does

## When to Use
Situations where this skill applies

## How to Use
Step-by-step instructions

## Example
Concrete example of the skill in action
```

Reference in agent instructions:
```markdown
Use the "Custom Skill Name" skill when [condition].
```

## Troubleshooting

### Proxy Returns 401 Unauthorized

**Cause:** Wrong authentication method or expired credentials.

**Solution:**
1. Unset `GOOGLE_APPLICATION_CREDENTIALS`:
   ```bash
   unset GOOGLE_APPLICATION_CREDENTIALS
   ```

2. Re-authenticate with gcloud:
   ```bash
   gcloud auth application-default login
   ```

3. Restart the proxy:
   ```bash
   # macOS
   launchctl unload ~/Library/LaunchAgents/com.user.vertex-ai-proxy.plist
   launchctl load ~/Library/LaunchAgents/com.user.vertex-ai-proxy.plist

   # Windows
   nssm restart VertexAIProxy
   ```

### Heartbeat Not Sending to Slack

**Cause:** Missing Slack tokens or wrong channel ID.

**Solution:**
1. Verify tokens in `~/.openclaw/.env`:
   ```bash
   cat ~/.openclaw/.env | grep SLACK
   ```

2. Test Slack connection:
   ```bash
   curl -X POST https://slack.com/api/chat.postMessage \
     -H "Authorization: Bearer xoxb-YOUR-TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"channel":"C01234567","text":"Test"}'
   ```

3. Check channel ID is correct (starts with `C`).

### LaunchD Service Won't Start (macOS)

**Cause:** PATH environment variable missing gcloud.

**Solution:**
1. Find gcloud path:
   ```bash
   which gcloud
   ```

2. Update plist with full PATH:
   ```xml
   <key>EnvironmentVariables</key>
   <dict>
       <key>PATH</key>
       <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Users/YOURUSERNAME/google-cloud-sdk/bin</string>
   </dict>
   ```

3. Reload service:
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.user.vertex-ai-proxy.plist
   launchctl load ~/Library/LaunchAgents/com.user.vertex-ai-proxy.plist
   ```

### Streaming Responses Not Working

**Cause:** Proxy not detecting `stream: true` parameter.

**Solution:**
1. Verify proxy version has streaming support:
   ```bash
   grep "client.stream()" ~/vertex-ai-proxy/proxy.py
   ```

2. If missing, update proxy code (see `FOR-CLAUDE.md` section 7.4).

3. Restart proxy service.

### Code Changes Not Taking Effect

**Cause:** Service running old code (not restarted after changes).

**Solution:**
Always restart services after code changes:

```bash
# macOS
launchctl unload ~/Library/LaunchAgents/com.user.vertex-ai-proxy.plist
launchctl load ~/Library/LaunchAgents/com.user.vertex-ai-proxy.plist

# Windows
nssm restart VertexAIProxy
```

Verify process start time matches code update:
```bash
ps aux | grep proxy.py
ls -l ~/vertex-ai-proxy/proxy.py
```

### Files Not Syncing Between Workspaces

**Cause:** OpenClaw has two separate workspace locations.

**Understanding:**
- Main workspace: `~/.openclaw/workspace/` (system config)
- Sandbox workspace: `~/.openclaw/sandboxes/agent-main-*/` (agent files)

**Solution:**
1. System files (SOUL.md, AGENTS.md, TOOLS.md) go in main workspace.
2. Agent-specific files (USER.md, HEARTBEAT.md, context files) go in sandbox workspace.
3. Manually copy when needed:
   ```bash
   cp ~/.openclaw/workspace/SOUL.md ~/.openclaw/sandboxes/agent-main-*/
   ```

### Docker Container Permission Denied

**Cause:** Container trying to write to read-only filesystem.

**Solution:**
1. Verify volume mount has write permissions:
   ```bash
   docker run --rm \
     -v ~/.openclaw/sandboxes/agent-main-*:/workspace \
     openclaw-sandbox:latest \
     touch /workspace/test.txt
   ```

2. Check Docker configuration in `.env`:
   ```bash
   DOCKER_SANDBOX_READ_ONLY=false  # Temporarily for testing
   ```

3. Ensure workspace directory has correct ownership:
   ```bash
   chown -R $(whoami) ~/.openclaw/sandboxes
   ```

## Cost Estimates

### Gemini Pricing (as of Feb 2025)

**Gemini 2.5 Flash:**
- Input: $0.075 per 1M tokens
- Output: $0.30 per 1M tokens
- Cached input: $0.01875 per 1M tokens (75% discount)

**Gemini 2.5 Pro:**
- Input: $1.25 per 1M tokens
- Output: $5.00 per 1M tokens
- Cached input: $0.3125 per 1M tokens (75% discount)

### Heartbeat Cost Calculation

**Assumptions:**
- Heartbeat every 30 minutes = 48 per day
- Input per heartbeat: ~135K tokens (SOUL.md, AGENTS.md, context files)
- Output per heartbeat: ~500 tokens (status update)
- Model: Gemini 2.5 Flash

**Daily cost:**
```
Input:  48 × 135,000 × $0.075 / 1,000,000 = $0.486
Output: 48 × 500 × $0.30 / 1,000,000 = $0.0072
Total: ~$0.49/day or ~$15/month
```

**With caching (after first heartbeat):**
```
Input (cached):  48 × 135,000 × $0.01875 / 1,000,000 = $0.12
Output: 48 × 500 × $0.30 / 1,000,000 = $0.0072
Total: ~$0.13/day or ~$4/month
```

### Cost Calculator Examples

**Light usage (personal project):**
- Heartbeats: $4/month
- Development work: ~500K tokens/month = $0.15/month
- Total: ~$5/month

**Medium usage (active development):**
- Heartbeats: $4/month
- Development work: ~5M tokens/month = $1.50/month
- Code reviews: ~2M tokens/month = $0.60/month
- Total: ~$6/month

**Heavy usage (team environment):**
- Heartbeats: $4/month
- Development work: ~20M tokens/month = $6/month
- Code reviews: ~10M tokens/month = $3/month
- Planning sessions: ~5M tokens/month = $1.50/month
- Total: ~$15/month

**Tips to reduce costs:**
1. Adjust heartbeat frequency (60 min instead of 30 min = half the cost)
2. Use Flash model for routine tasks, Pro only for complex reasoning
3. Enable prompt caching (automatic in Vertex AI)
4. Set max token limits in agent configs
5. Archive old sessions to reduce context size

## Security

### Docker Isolation

The sandbox container runs with maximum security:

- **Read-only root filesystem**: Prevents malicious file modifications
- **Dropped ALL capabilities**: No privileged operations allowed
- **Non-root user**: Container runs as UID 1000
- **Bridge network**: No direct internet access
- **Volume mounts**: Only workspace directory accessible

Verify security settings:
```bash
docker inspect openclaw-sandbox:latest | jq '.[0].Config.User'
# Should show: "sandbox" or "1000"
```

### Secrets Management

**Best practices:**

1. **Never commit secrets to git**
   ```bash
   echo ".env" >> ~/.openclaw/.gitignore
   echo "*.pem" >> ~/.openclaw/.gitignore
   ```

2. **Use 1Password for token storage**
   ```bash
   op item create --category=login \
     --title="OpenClaw Secrets" \
     --field="slack_bot_token=xoxb-..." \
     --field="slack_app_token=xapp-..."
   ```

3. **Restrict .env file permissions**
   ```bash
   chmod 600 ~/.openclaw/.env
   chmod 600 ~/vertex-ai-proxy/.env
   ```

4. **Use environment-specific configs**
   ```bash
   # Development
   cp .env.example .env.dev

   # Production
   cp .env.example .env.prod
   ```

5. **Rotate tokens regularly**
   - Slack tokens: Every 90 days
   - GCP credentials: Re-authenticate monthly

### Slack Security

**Allowlist configuration:**

In your Slack app settings:
1. Go to "OAuth & Permissions"
2. Under "Restrict API Token Usage", add:
   - Your IP address
   - Your VPN IP range (if applicable)
3. Enable "Require apps to be added to channels"

**Recommended scopes (minimum required):**
- `chat:write` - Send messages only
- `channels:read` - Read public channel info only
- `im:read` - Read DM info only

**Avoid these scopes unless necessary:**
- `chat:write.customize` - Can impersonate users
- `channels:write` - Can create/archive channels
- `files:write` - Can upload files
- `admin.*` - Admin permissions

### Network Security

**Proxy security:**
1. Bind to localhost only (`HOST=127.0.0.1`)
2. Don't expose port 8000 externally
3. Use firewall to block external access:
   ```bash
   # macOS
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/local/bin/python3
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --block /usr/local/bin/python3
   ```

**OpenClaw security:**
1. Use Docker bridge network (no direct internet)
2. Proxy external API calls through host
3. Allowlist domains if needed:
   ```bash
   ALLOWED_DOMAINS=github.com,api.slack.com
   ```

## Appendix: Custom Skills

### What Are Skills?

Skills are reusable prompt templates that guide agents through complex tasks. They're inspired by Emanuel's prompt engineering techniques.

### Available Skills

The setup guide includes these optional skills:

1. **fresh-eyes.md** - Re-read code after changes to catch bugs
2. **bug-hunt.md** - Systematically explore codebase for issues
3. **idea-wizard.md** - Generate and evaluate 30 ideas for planning
4. **plan-review.md** - Multi-pass plan refinement with fresh eyes
5. **peer-review.md** - Cross-agent code review protocol

### Installing Skills

```bash
cp ~/openclaw-setup-guide/skills/*.md ~/.openclaw/workspace/skills/
```

### Using Skills in Agents

Edit `~/.openclaw/workspace/AGENTS.md`:

```markdown
## Developer Agent

Instructions:
- ALWAYS use "fresh-eyes" skill after writing code
- Use "bug-hunt" skill when investigating issues
- Use "peer-review" skill before marking tasks complete
```

### Creating Custom Skills

Template structure:

```markdown
# Skill Name

## Purpose
Brief description of what this skill accomplishes

## When to Use
- Trigger condition 1
- Trigger condition 2

## Protocol

1. Step 1 with specific instructions
2. Step 2 with specific instructions
3. Step 3 with specific instructions

## Output Format

Expected output format

## Example

Concrete example of the skill in action
```

Save as `~/.openclaw/workspace/skills/your-skill.md`

---

## Next Steps

1. **Review FOR-CLAUDE.md** - The mechanical checklist version for Claude to execute
2. **Test the system** - Send a message in Slack, verify heartbeat
3. **Customize agents** - Tailor AGENTS.md to your workflow
4. **Add project context** - Create context files for your projects
5. **Monitor costs** - Check GCP billing after first week
6. **Iterate** - Adjust reasoning levels, heartbeat frequency, agent instructions

## Support

- **OpenClaw GitHub**: https://github.com/ckreiling/openclaw
- **Vertex AI Docs**: https://cloud.google.com/vertex-ai/docs
- **Slack API Docs**: https://api.slack.com/docs
- **This guide**: https://github.com/YOUR_USERNAME/openclaw-setup-guide

## Contributing

Found an issue or improvement? Submit a PR or open an issue on the setup guide repository.

---

**Last updated:** 2026-02-09
**Guide version:** 1.0.0
**OpenClaw version:** Latest from main branch
