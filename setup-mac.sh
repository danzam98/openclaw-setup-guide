#!/bin/bash

# OpenClaw + Vertex AI Proxy - macOS Setup Script
# This script automates the complete setup process for running OpenClaw with Gemini via Vertex AI

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Global state
STEP=0
TOTAL_STEPS=15
BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)

#################################################
# Helper Functions
#################################################

print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}================================================${NC}"
    echo -e "${CYAN}${BOLD}   OpenClaw + Vertex AI Proxy - Setup Script${NC}"
    echo -e "${CYAN}${BOLD}================================================${NC}"
    echo ""
}

print_step() {
    STEP=$((STEP + 1))
    echo ""
    echo -e "${CYAN}${BOLD}[Step $STEP/$TOTAL_STEPS]${NC} $1"
    echo -e "${CYAN}----------------------------------------${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗ ERROR:${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -p "$prompt" response
    response=${response:-$default}

    [[ "$response" =~ ^[Yy]$ ]]
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup.${BACKUP_SUFFIX}"
        cp "$file" "$backup"
        print_info "Backed up existing file to: $backup"
    fi
}

#################################################
# Step 1: Prerequisites Check
#################################################

check_prerequisites() {
    print_step "Checking prerequisites"

    local missing_tools=()
    local tools=("node" "python3" "docker" "gcloud" "npm" "git")

    for tool in "${tools[@]}"; do
        if command_exists "$tool"; then
            local version=""
            case "$tool" in
                node) version=$(node --version) ;;
                python3) version=$(python3 --version) ;;
                docker) version=$(docker --version) ;;
                gcloud) version=$(gcloud version 2>&1 | head -n1) ;;
                npm) version=$(npm --version) ;;
                git) version=$(git --version) ;;
            esac
            print_success "$tool found: $version"
        else
            print_warning "$tool not found"
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo ""
        print_error "Missing required tools: ${missing_tools[*]}"

        if command_exists brew; then
            echo ""
            if ask_yes_no "Install missing tools via Homebrew?" "y"; then
                for tool in "${missing_tools[@]}"; do
                    case "$tool" in
                        node|npm)
                            print_info "Installing Node.js..."
                            brew install node
                            ;;
                        python3)
                            print_info "Installing Python 3..."
                            brew install python@3
                            ;;
                        docker)
                            print_info "Installing Docker..."
                            brew install --cask docker
                            print_warning "Docker Desktop requires manual launch after installation"
                            ;;
                        gcloud)
                            print_info "Installing Google Cloud SDK..."
                            brew install --cask google-cloud-sdk
                            ;;
                        git)
                            print_info "Installing Git..."
                            brew install git
                            ;;
                    esac
                done
                print_success "Tools installed. Please restart Docker Desktop if it was installed."
            else
                print_error "Please install missing tools manually and re-run this script"
                exit 1
            fi
        else
            print_error "Homebrew not found. Install from: https://brew.sh"
            print_error "Or install missing tools manually and re-run this script"
            exit 1
        fi
    fi

    # Check Docker is running
    if ! docker ps >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker Desktop and re-run this script."
        exit 1
    fi
    print_success "Docker is running"
}

#################################################
# Step 2: Collect Configuration
#################################################

collect_config() {
    print_step "Collecting configuration"

    echo ""
    print_info "This script will prompt for required configuration values."
    print_info "Press Enter to accept defaults shown in [brackets]"
    echo ""

    # GCP Configuration
    read -p "GCP Project ID: " GCP_PROJECT
    while [[ -z "$GCP_PROJECT" ]]; do
        print_error "GCP Project ID is required"
        read -p "GCP Project ID: " GCP_PROJECT
    done

    read -p "GCP Region [us-central1]: " GCP_REGION
    GCP_REGION=${GCP_REGION:-us-central1}

    read -p "Gemini Model [gemini-2.0-flash-exp]: " GEMINI_MODEL
    GEMINI_MODEL=${GEMINI_MODEL:-gemini-2.0-flash-exp}

    # OpenClaw Configuration
    read -p "Main agent name [Steve]: " AGENT_NAME
    AGENT_NAME=${AGENT_NAME:-Steve}

    read -p "Anthropic API Key: " ANTHROPIC_API_KEY
    while [[ -z "$ANTHROPIC_API_KEY" ]]; do
        print_error "Anthropic API Key is required"
        read -p "Anthropic API Key: " ANTHROPIC_API_KEY
    done

    # Optional tokens
    read -p "GitHub Token (optional, press Enter to skip): " GITHUB_TOKEN
    read -p "1Password Connect Token (optional, press Enter to skip): " OP_CONNECT_TOKEN

    # Paths
    OPENCLAW_DIR="$HOME/.openclaw"
    PROXY_DIR="$HOME/vertex-ai-proxy"
    WORKSPACE_DIR="$OPENCLAW_DIR/workspace"
    LOGS_DIR="$OPENCLAW_DIR/logs"

    # User/Group for Docker
    DOCKER_USER=$(id -u)
    DOCKER_GROUP=$(id -g)

    echo ""
    print_info "Configuration collected:"
    echo "  GCP Project: $GCP_PROJECT"
    echo "  GCP Region: $GCP_REGION"
    echo "  Gemini Model: $GEMINI_MODEL"
    echo "  Agent Name: $AGENT_NAME"
    echo "  OpenClaw Dir: $OPENCLAW_DIR"
    echo "  Proxy Dir: $PROXY_DIR"
    echo ""
}

#################################################
# Step 3: Install OpenClaw
#################################################

install_openclaw() {
    print_step "Installing OpenClaw"

    if command_exists openclaw; then
        print_info "OpenClaw already installed at: $(which openclaw)"
        if ask_yes_no "Reinstall/update OpenClaw?" "n"; then
            npm install -g @firtoz/openclaw
            print_success "OpenClaw updated"
        else
            print_success "Using existing OpenClaw installation"
        fi
    else
        print_info "Installing OpenClaw globally via npm..."
        npm install -g @firtoz/openclaw
        print_success "OpenClaw installed at: $(which openclaw)"
    fi
}

#################################################
# Step 4: Setup Vertex AI Proxy
#################################################

setup_vertex_proxy() {
    print_step "Setting up Vertex AI Proxy"

    if [[ -d "$PROXY_DIR" ]]; then
        print_warning "Proxy directory already exists: $PROXY_DIR"
        if ask_yes_no "Remove and re-clone?" "n"; then
            rm -rf "$PROXY_DIR"
        else
            print_info "Using existing proxy directory"
            cd "$PROXY_DIR"
            print_info "Pulling latest changes..."
            git pull || print_warning "Failed to pull latest changes"
            cd - > /dev/null
        fi
    fi

    if [[ ! -d "$PROXY_DIR" ]]; then
        print_info "Cloning Vertex AI Proxy repository..."
        git clone https://github.com/anthropics/anthropic-vertex-ai-proxy.git "$PROXY_DIR"
        print_success "Proxy cloned"
    fi

    # Create virtual environment
    cd "$PROXY_DIR"
    if [[ ! -d "venv" ]]; then
        print_info "Creating Python virtual environment..."
        python3 -m venv venv
        print_success "Virtual environment created"
    else
        print_success "Virtual environment already exists"
    fi

    # Install dependencies
    print_info "Installing Python dependencies..."
    source venv/bin/activate
    pip install --upgrade pip -q
    pip install -r requirements.txt -q
    deactivate
    print_success "Dependencies installed"

    # Create .env file
    backup_file "$PROXY_DIR/.env"
    cat > "$PROXY_DIR/.env" <<EOF
PORT=8000
PROJECT_ID=$GCP_PROJECT
REGION=$GCP_REGION
MODEL_ID=$GEMINI_MODEL
EOF
    print_success "Proxy .env file created"

    cd - > /dev/null
}

#################################################
# Step 5: GCloud Authentication
#################################################

setup_gcloud_auth() {
    print_step "Setting up Google Cloud authentication"

    print_info "Checking gcloud authentication status..."
    if gcloud auth application-default print-access-token >/dev/null 2>&1; then
        print_success "Already authenticated with Application Default Credentials"
        if ! ask_yes_no "Re-authenticate?" "n"; then
            return
        fi
    fi

    print_info "Running: gcloud auth application-default login"
    print_info "This will open a browser window for authentication..."
    echo ""

    if gcloud auth application-default login; then
        print_success "Authentication successful"
    else
        print_error "Authentication failed"
        exit 1
    fi
}

#################################################
# Step 6: Build Docker Sandbox Image
#################################################

build_docker_image() {
    print_step "Building Docker sandbox image"

    print_info "Building openclaw-sandbox image..."
    print_info "This may take a few minutes on first run..."

    cd "$PROXY_DIR"
    if docker build -t openclaw-sandbox -f Dockerfile.sandbox . ; then
        print_success "Docker image built successfully"
    else
        print_error "Docker build failed"
        exit 1
    fi
    cd - > /dev/null
}

#################################################
# Step 7: Create OpenClaw Configuration
#################################################

create_openclaw_config() {
    print_step "Creating OpenClaw configuration"

    mkdir -p "$OPENCLAW_DIR"
    mkdir -p "$WORKSPACE_DIR"
    mkdir -p "$LOGS_DIR"

    # Create openclaw.json
    backup_file "$OPENCLAW_DIR/openclaw.json"
    cat > "$OPENCLAW_DIR/openclaw.json" <<EOF
{
  "agents": {
    "main": {
      "name": "$AGENT_NAME",
      "provider": "anthropic",
      "model": "claude-sonnet-4-5",
      "systemPromptFile": "SOUL.md",
      "maxTokens": 8000,
      "sandboxConfig": {
        "type": "docker",
        "image": "openclaw-sandbox",
        "user": "$DOCKER_USER:$DOCKER_GROUP",
        "mounts": [
          {
            "type": "bind",
            "source": "$WORKSPACE_DIR",
            "target": "/workspace"
          }
        ],
        "environment": {},
        "capabilities": {
          "drop": ["ALL"]
        },
        "readOnlyRootfs": true,
        "securityOpt": ["no-new-privileges:true"]
      }
    }
  },
  "mcpServers": {},
  "workspaceDir": "$WORKSPACE_DIR",
  "apiKeys": {
    "anthropic": "\${ANTHROPIC_API_KEY}"$([ -n "${GITHUB_TOKEN:-}" ] && echo ",
    \"github\": \"\${GITHUB_TOKEN}\"")$([ -n "${OP_CONNECT_TOKEN:-}" ] && echo ",
    \"onepassword\": \"\${OP_CONNECT_TOKEN}\"")
  },
  "server": {
    "port": 18789,
    "host": "127.0.0.1"
  }
}
EOF
    print_success "openclaw.json created"

    # Create .env file
    backup_file "$OPENCLAW_DIR/.env"
    cat > "$OPENCLAW_DIR/.env" <<EOF
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
EOF

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "GITHUB_TOKEN=$GITHUB_TOKEN" >> "$OPENCLAW_DIR/.env"
    fi

    if [[ -n "${OP_CONNECT_TOKEN:-}" ]]; then
        echo "OP_CONNECT_TOKEN=$OP_CONNECT_TOKEN" >> "$OPENCLAW_DIR/.env"
    fi

    print_success ".env file created"
}

#################################################
# Step 8: Create Workspace Files
#################################################

create_workspace_files() {
    print_step "Creating workspace files"

    # SOUL.md
    backup_file "$WORKSPACE_DIR/SOUL.md"
    cat > "$WORKSPACE_DIR/SOUL.md" <<'EOF'
# System Prompt for OpenClaw Agent

You are an AI agent running within the OpenClaw framework. You have access to various tools and can execute commands within a sandboxed environment.

## Your Role
- Proactive problem-solving
- Code analysis and development
- System monitoring and maintenance
- Documentation and knowledge management

## Guidelines
- Always verify before taking destructive actions
- Write clear, maintainable code
- Document your decisions
- Ask for clarification when uncertain

## Available Tools
You have access to bash commands, file operations, and various programming tools within your sandbox environment.
EOF
    print_success "SOUL.md created"

    # AGENTS.md
    backup_file "$WORKSPACE_DIR/AGENTS.md"
    cat > "$WORKSPACE_DIR/AGENTS.md" <<EOF
# Agent Configuration

## Main Agent: $AGENT_NAME
- Provider: Anthropic
- Model: claude-sonnet-4-5
- Sandbox: Docker (openclaw-sandbox)
- Security: Read-only root, no capabilities

## Capabilities
- File system access (workspace only)
- Command execution (sandboxed)
- Network access (via host)
EOF
    print_success "AGENTS.md created"

    # USER.md
    backup_file "$WORKSPACE_DIR/USER.md"
    cat > "$WORKSPACE_DIR/USER.md" <<'EOF'
# User Context

This file contains information about the user and their preferences.

## User Information
- Setup date: $(date)
- Primary agent: $AGENT_NAME

## Preferences
- Communication style: Clear and concise
- Code style: Follow project conventions
- Error handling: Always include proper error handling
EOF
    print_success "USER.md created"

    # HEARTBEAT.md
    backup_file "$WORKSPACE_DIR/HEARTBEAT.md"
    cat > "$WORKSPACE_DIR/HEARTBEAT.md" <<'EOF'
# Heartbeat Instructions

This file is read every 30 minutes by the agent to check for tasks and updates.

## Tasks
- Check for system health issues
- Monitor log files for errors
- Check for pending work
- Update status files

## Status
Last check: (Will be updated by agent)
EOF
    print_success "HEARTBEAT.md created"

    # BOOTSTRAP.md
    backup_file "$WORKSPACE_DIR/BOOTSTRAP.md"
    cat > "$WORKSPACE_DIR/BOOTSTRAP.md" <<'EOF'
# Bootstrap Instructions

This file contains initial setup instructions for the agent on first run.

## Initial Tasks
1. Verify workspace access
2. Check tool availability
3. Read USER.md and AGENTS.md
4. Initialize logging

## Verification
- Workspace writable: [ ]
- Commands available: [ ]
- Context loaded: [ ]
EOF
    print_success "BOOTSTRAP.md created"
}

#################################################
# Step 9: Create LaunchD Services
#################################################

create_launchd_services() {
    print_step "Creating LaunchD services"

    local launchd_dir="$HOME/Library/LaunchAgents"
    mkdir -p "$launchd_dir"

    # Get PATH from current shell
    local shell_path="$PATH"

    # Vertex AI Proxy plist
    local proxy_plist="$launchd_dir/com.user.vertex-ai-proxy.plist"
    backup_file "$proxy_plist"
    cat > "$proxy_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.vertex-ai-proxy</string>

    <key>ProgramArguments</key>
    <array>
        <string>$PROXY_DIR/venv/bin/python</string>
        <string>$PROXY_DIR/proxy.py</string>
    </array>

    <key>WorkingDirectory</key>
    <string>$PROXY_DIR</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$shell_path</string>
    </dict>

    <key>StandardOutPath</key>
    <string>$LOGS_DIR/vertex-proxy.log</string>

    <key>StandardErrorPath</key>
    <string>$LOGS_DIR/vertex-proxy.error.log</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
    print_success "Vertex AI Proxy plist created"

    # OpenClaw Gateway plist
    local openclaw_bin=$(which openclaw)
    local gateway_plist="$launchd_dir/com.user.openclaw-gateway.plist"
    backup_file "$gateway_plist"
    cat > "$gateway_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.openclaw-gateway</string>

    <key>ProgramArguments</key>
    <array>
        <string>$openclaw_bin</string>
        <string>gateway</string>
        <string>start</string>
    </array>

    <key>WorkingDirectory</key>
    <string>$OPENCLAW_DIR</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$shell_path</string>
    </dict>

    <key>StandardOutPath</key>
    <string>$LOGS_DIR/gateway.log</string>

    <key>StandardErrorPath</key>
    <string>$LOGS_DIR/gateway.error.log</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
    print_success "OpenClaw Gateway plist created"

    # Set correct permissions
    chmod 644 "$proxy_plist"
    chmod 644 "$gateway_plist"
}

#################################################
# Step 10: Load LaunchD Services
#################################################

load_launchd_services() {
    print_step "Loading LaunchD services"

    local proxy_plist="$HOME/Library/LaunchAgents/com.user.vertex-ai-proxy.plist"
    local gateway_plist="$HOME/Library/LaunchAgents/com.user.openclaw-gateway.plist"

    # Unload if already loaded
    launchctl unload "$proxy_plist" 2>/dev/null || true
    launchctl unload "$gateway_plist" 2>/dev/null || true

    # Load services
    print_info "Loading Vertex AI Proxy service..."
    if launchctl load "$proxy_plist"; then
        print_success "Vertex AI Proxy service loaded"
    else
        print_error "Failed to load Vertex AI Proxy service"
        exit 1
    fi

    print_info "Loading OpenClaw Gateway service..."
    if launchctl load "$gateway_plist"; then
        print_success "OpenClaw Gateway service loaded"
    else
        print_error "Failed to load OpenClaw Gateway service"
        exit 1
    fi
}

#################################################
# Step 11: Wait for Services
#################################################

wait_for_services() {
    print_step "Waiting for services to start"

    print_info "Waiting for services to initialize..."
    sleep 5

    local max_attempts=12
    local attempt=0

    # Wait for proxy
    print_info "Checking Vertex AI Proxy health..."
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s http://127.0.0.1:8000/health >/dev/null 2>&1; then
            print_success "Vertex AI Proxy is healthy"
            break
        fi
        attempt=$((attempt + 1))
        if [[ $attempt -eq $max_attempts ]]; then
            print_error "Vertex AI Proxy failed to start"
            print_info "Check logs at: $LOGS_DIR/vertex-proxy.error.log"
            exit 1
        fi
        sleep 2
    done

    # Wait for gateway
    attempt=0
    print_info "Checking OpenClaw Gateway health..."
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s http://127.0.0.1:18789/health >/dev/null 2>&1; then
            print_success "OpenClaw Gateway is healthy"
            break
        fi
        attempt=$((attempt + 1))
        if [[ $attempt -eq $max_attempts ]]; then
            print_error "OpenClaw Gateway failed to start"
            print_info "Check logs at: $LOGS_DIR/gateway.error.log"
            exit 1
        fi
        sleep 2
    done
}

#################################################
# Step 12: Run Verification Tests
#################################################

run_verification() {
    print_step "Running verification tests"

    # Test proxy health
    print_info "Testing Vertex AI Proxy..."
    local proxy_health=$(curl -s http://127.0.0.1:8000/health)
    if [[ "$proxy_health" == *"ok"* ]]; then
        print_success "Proxy health check passed"
    else
        print_warning "Proxy health check returned unexpected response: $proxy_health"
    fi

    # Test gateway health
    print_info "Testing OpenClaw Gateway..."
    local gateway_health=$(curl -s http://127.0.0.1:18789/health)
    if [[ -n "$gateway_health" ]]; then
        print_success "Gateway health check passed"
    else
        print_warning "Gateway health check returned empty response"
    fi

    # Check Docker image
    print_info "Verifying Docker sandbox image..."
    if docker images openclaw-sandbox --format "{{.Repository}}" | grep -q openclaw-sandbox; then
        print_success "Docker sandbox image found"
    else
        print_error "Docker sandbox image not found"
    fi

    # Check workspace files
    print_info "Verifying workspace files..."
    local workspace_files=("SOUL.md" "AGENTS.md" "USER.md" "HEARTBEAT.md" "BOOTSTRAP.md")
    for file in "${workspace_files[@]}"; do
        if [[ -f "$WORKSPACE_DIR/$file" ]]; then
            print_success "$file exists"
        else
            print_warning "$file not found"
        fi
    done
}

#################################################
# Step 13: Print Summary
#################################################

print_summary() {
    print_step "Setup Complete!"

    echo ""
    echo -e "${GREEN}${BOLD}========================================${NC}"
    echo -e "${GREEN}${BOLD}   OpenClaw is ready to use!${NC}"
    echo -e "${GREEN}${BOLD}========================================${NC}"
    echo ""

    print_info "Configuration:"
    echo "  • OpenClaw Config: $OPENCLAW_DIR/openclaw.json"
    echo "  • Workspace: $WORKSPACE_DIR"
    echo "  • Logs: $LOGS_DIR"
    echo "  • Proxy: http://127.0.0.1:8000"
    echo "  • Gateway: http://127.0.0.1:18789"
    echo ""

    print_info "Services:"
    echo "  • Vertex AI Proxy: Running via LaunchD"
    echo "  • OpenClaw Gateway: Running via LaunchD"
    echo ""

    print_info "Next Steps:"
    echo ""
    echo "  1. Test the agent:"
    echo "     ${CYAN}openclaw chat \"Hello, $AGENT_NAME!\"${NC}"
    echo ""
    echo "  2. View logs:"
    echo "     ${CYAN}tail -f $LOGS_DIR/vertex-proxy.log${NC}"
    echo "     ${CYAN}tail -f $LOGS_DIR/gateway.log${NC}"
    echo ""
    echo "  3. Restart services if needed:"
    echo "     ${CYAN}launchctl unload ~/Library/LaunchAgents/com.user.vertex-ai-proxy.plist${NC}"
    echo "     ${CYAN}launchctl load ~/Library/LaunchAgents/com.user.vertex-ai-proxy.plist${NC}"
    echo ""
    echo "  4. Check service status:"
    echo "     ${CYAN}launchctl list | grep com.user${NC}"
    echo ""

    print_success "Setup completed successfully!"
    echo ""
}

#################################################
# Main Execution
#################################################

main() {
    print_banner

    print_info "This script will set up OpenClaw with Vertex AI Proxy on your Mac."
    print_info "The process will take 5-10 minutes and requires internet access."
    echo ""

    if ! ask_yes_no "Continue with setup?" "y"; then
        print_info "Setup cancelled"
        exit 0
    fi

    check_prerequisites
    collect_config
    install_openclaw
    setup_vertex_proxy
    setup_gcloud_auth
    build_docker_image
    create_openclaw_config
    create_workspace_files
    create_launchd_services
    load_launchd_services
    wait_for_services
    run_verification
    print_summary
}

# Run main function
main "$@"
