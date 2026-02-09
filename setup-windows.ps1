# OpenClaw + Vertex AI Proxy - Windows Setup Script
# This script automates the complete setup process for running OpenClaw with Gemini via Vertex AI

#Requires -Version 5.1

# Set strict error handling
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

# Global state
$script:Step = 0
$script:TotalSteps = 15
$script:BackupSuffix = Get-Date -Format "yyyyMMdd_HHmmss"

#################################################
# Helper Functions
#################################################

function Print-Banner {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "   OpenClaw + Vertex AI Proxy - Setup Script" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Print-Step {
    param([string]$Message)
    $script:Step++
    Write-Host ""
    Write-Host "[Step $script:Step/$script:TotalSteps] $Message" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Cyan
}

function Print-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Print-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Print-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Print-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Ask-YesNo {
    param(
        [string]$Prompt,
        [string]$Default = "n"
    )

    $options = if ($Default -eq "y") { "[Y/n]" } else { "[y/N]" }
    $response = Read-Host "$Prompt $options"

    if ([string]::IsNullOrWhiteSpace($response)) {
        $response = $Default
    }

    return $response -match '^[Yy]$'
}

function Test-CommandExists {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Backup-File {
    param([string]$FilePath)

    if (Test-Path $FilePath) {
        $backup = "$FilePath.backup.$script:BackupSuffix"
        Copy-Item $FilePath $backup
        Print-Info "Backed up existing file to: $backup"
    }
}

#################################################
# Step 1: Check Administrator Privileges
#################################################

function Test-Administrator {
    Print-Step "Checking administrator privileges"

    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Print-Error "This script must be run as Administrator"
        Print-Info "Right-click PowerShell and select 'Run as Administrator', then run this script again"
        exit 1
    }

    Print-Success "Running as Administrator"
}

#################################################
# Step 2: Prerequisites Check
#################################################

function Test-Prerequisites {
    Print-Step "Checking prerequisites"

    $missingTools = @()
    $tools = @{
        "node" = "Node.js"
        "python" = "Python 3"
        "docker" = "Docker"
        "gcloud" = "Google Cloud SDK"
        "npm" = "npm"
        "git" = "Git"
    }

    foreach ($tool in $tools.Keys) {
        if (Test-CommandExists $tool) {
            $version = switch ($tool) {
                "node" { & node --version }
                "python" { & python --version }
                "docker" { & docker --version }
                "gcloud" { (& gcloud version 2>&1)[0] }
                "npm" { & npm --version }
                "git" { & git --version }
            }
            Print-Success "$($tools[$tool]) found: $version"
        }
        else {
            Print-Warning "$($tools[$tool]) not found"
            $missingTools += $tool
        }
    }

    if ($missingTools.Count -gt 0) {
        Write-Host ""
        Print-Error "Missing required tools: $($missingTools -join ', ')"

        if (Test-CommandExists "winget") {
            Write-Host ""
            if (Ask-YesNo "Install missing tools via winget?" "y") {
                foreach ($tool in $missingTools) {
                    switch ($tool) {
                        "node" {
                            Print-Info "Installing Node.js..."
                            winget install OpenJS.NodeJS.LTS --silent
                        }
                        "npm" {
                            Print-Info "npm comes with Node.js (will be installed)"
                        }
                        "python" {
                            Print-Info "Installing Python 3..."
                            winget install Python.Python.3.12 --silent
                        }
                        "docker" {
                            Print-Info "Installing Docker Desktop..."
                            winget install Docker.DockerDesktop --silent
                            Print-Warning "Docker Desktop requires manual launch and configuration after installation"
                        }
                        "gcloud" {
                            Print-Info "Installing Google Cloud SDK..."
                            winget install Google.CloudSDK --silent
                        }
                        "git" {
                            Print-Info "Installing Git..."
                            winget install Git.Git --silent
                        }
                    }
                }
                Print-Success "Tools installed. Please restart PowerShell to refresh PATH"
                Print-Warning "Start Docker Desktop manually, then re-run this script"
                exit 0
            }
            else {
                Print-Error "Please install missing tools manually and re-run this script"
                exit 1
            }
        }
        else {
            Print-Error "winget not found. Please install Windows Package Manager or install tools manually"
            Print-Info "Download from: https://apps.microsoft.com/store/detail/app-installer/9NBLGGH4NNS1"
            exit 1
        }
    }

    # Check Docker is running
    Print-Info "Checking if Docker is running..."
    $dockerProcess = Get-Process "Docker Desktop" -ErrorAction SilentlyContinue
    if (-not $dockerProcess) {
        Print-Error "Docker Desktop is not running"
        Print-Info "Please start Docker Desktop and re-run this script"
        exit 1
    }

    try {
        $null = docker ps 2>&1
        Print-Success "Docker is running"
    }
    catch {
        Print-Error "Docker is running but not responding. Please check Docker Desktop status"
        exit 1
    }
}

#################################################
# Step 3: Collect Configuration
#################################################

function Get-Configuration {
    Print-Step "Collecting configuration"

    Write-Host ""
    Print-Info "This script will prompt for required configuration values."
    Print-Info "Press Enter to accept defaults shown in [brackets]"
    Write-Host ""

    # GCP Configuration
    do {
        $script:GcpProject = Read-Host "GCP Project ID"
    } while ([string]::IsNullOrWhiteSpace($script:GcpProject))

    $gcpRegionInput = Read-Host "GCP Region [us-central1]"
    $script:GcpRegion = if ([string]::IsNullOrWhiteSpace($gcpRegionInput)) { "us-central1" } else { $gcpRegionInput }

    $geminiModelInput = Read-Host "Gemini Model [gemini-2.0-flash-exp]"
    $script:GeminiModel = if ([string]::IsNullOrWhiteSpace($geminiModelInput)) { "gemini-2.0-flash-exp" } else { $geminiModelInput }

    # OpenClaw Configuration
    $agentNameInput = Read-Host "Main agent name [Steve]"
    $script:AgentName = if ([string]::IsNullOrWhiteSpace($agentNameInput)) { "Steve" } else { $agentNameInput }

    do {
        $script:AnthropicApiKey = Read-Host "Anthropic API Key"
    } while ([string]::IsNullOrWhiteSpace($script:AnthropicApiKey))

    # Optional tokens
    $script:GitHubToken = Read-Host "GitHub Token (optional, press Enter to skip)"
    $script:OpConnectToken = Read-Host "1Password Connect Token (optional, press Enter to skip)"

    # Paths
    $script:OpenClawDir = Join-Path $env:USERPROFILE ".openclaw"
    $script:ProxyDir = Join-Path $env:USERPROFILE "vertex-ai-proxy"
    $script:WorkspaceDir = Join-Path $script:OpenClawDir "workspace"
    $script:LogsDir = Join-Path $script:OpenClawDir "logs"

    Write-Host ""
    Print-Info "Configuration collected:"
    Write-Host "  GCP Project: $script:GcpProject"
    Write-Host "  GCP Region: $script:GcpRegion"
    Write-Host "  Gemini Model: $script:GeminiModel"
    Write-Host "  Agent Name: $script:AgentName"
    Write-Host "  OpenClaw Dir: $script:OpenClawDir"
    Write-Host "  Proxy Dir: $script:ProxyDir"
    Write-Host ""
}

#################################################
# Step 4: Install NSSM
#################################################

function Install-NSSM {
    Print-Step "Installing NSSM (Non-Sucking Service Manager)"

    if (Test-CommandExists "nssm") {
        Print-Success "NSSM already installed"
        return
    }

    Print-Info "Installing NSSM via winget..."
    try {
        winget install nssm.nssm --silent

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        if (Test-CommandExists "nssm") {
            Print-Success "NSSM installed successfully"
        }
        else {
            Print-Warning "NSSM installed but not in PATH. Please restart PowerShell after setup completes."
        }
    }
    catch {
        Print-Error "Failed to install NSSM: $_"
        Print-Info "Please install manually from: https://nssm.cc/download"
        exit 1
    }
}

#################################################
# Step 5: Install OpenClaw
#################################################

function Install-OpenClaw {
    Print-Step "Installing OpenClaw"

    if (Test-CommandExists "openclaw") {
        Print-Info "OpenClaw already installed at: $(where.exe openclaw)"
        if (Ask-YesNo "Reinstall/update OpenClaw?" "n") {
            npm install -g @firtoz/openclaw
            Print-Success "OpenClaw updated"
        }
        else {
            Print-Success "Using existing OpenClaw installation"
        }
    }
    else {
        Print-Info "Installing OpenClaw globally via npm..."
        npm install -g @firtoz/openclaw

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        if (Test-CommandExists "openclaw") {
            Print-Success "OpenClaw installed at: $(where.exe openclaw)"
        }
        else {
            Print-Warning "OpenClaw installed but not in PATH. Please restart PowerShell after setup completes."
        }
    }
}

#################################################
# Step 6: Setup Vertex AI Proxy
#################################################

function Install-VertexProxy {
    Print-Step "Setting up Vertex AI Proxy"

    if (Test-Path $script:ProxyDir) {
        Print-Warning "Proxy directory already exists: $script:ProxyDir"
        if (Ask-YesNo "Remove and re-clone?" "n") {
            Remove-Item -Path $script:ProxyDir -Recurse -Force
        }
        else {
            Print-Info "Using existing proxy directory"
            Push-Location $script:ProxyDir
            Print-Info "Pulling latest changes..."
            try {
                git pull
            }
            catch {
                Print-Warning "Failed to pull latest changes: $_"
            }
            Pop-Location
        }
    }

    if (-not (Test-Path $script:ProxyDir)) {
        Print-Info "Cloning Vertex AI Proxy repository..."
        git clone https://github.com/anthropics/anthropic-vertex-ai-proxy.git $script:ProxyDir
        Print-Success "Proxy cloned"
    }

    # Create virtual environment
    Push-Location $script:ProxyDir

    if (-not (Test-Path "venv")) {
        Print-Info "Creating Python virtual environment..."
        python -m venv venv
        Print-Success "Virtual environment created"
    }
    else {
        Print-Success "Virtual environment already exists"
    }

    # Install dependencies
    Print-Info "Installing Python dependencies..."
    $venvPython = Join-Path $script:ProxyDir "venv\Scripts\python.exe"
    $venvPip = Join-Path $script:ProxyDir "venv\Scripts\pip.exe"

    & $venvPip install --upgrade pip --quiet
    & $venvPip install -r requirements.txt --quiet
    Print-Success "Dependencies installed"

    # Create .env file
    $envFile = Join-Path $script:ProxyDir ".env"
    Backup-File $envFile

    @"
PORT=8000
PROJECT_ID=$script:GcpProject
REGION=$script:GcpRegion
MODEL_ID=$script:GeminiModel
"@ | Out-File -FilePath $envFile -Encoding utf8

    Print-Success "Proxy .env file created"

    Pop-Location
}

#################################################
# Step 7: GCloud Authentication
#################################################

function Initialize-GCloudAuth {
    Print-Step "Setting up Google Cloud authentication"

    Print-Info "Checking gcloud authentication status..."
    try {
        $null = gcloud auth application-default print-access-token 2>&1
        Print-Success "Already authenticated with Application Default Credentials"
        if (-not (Ask-YesNo "Re-authenticate?" "n")) {
            return
        }
    }
    catch {
        Print-Info "Not authenticated yet"
    }

    Print-Info "Running: gcloud auth application-default login"
    Print-Info "This will open a browser window for authentication..."
    Write-Host ""

    try {
        gcloud auth application-default login
        Print-Success "Authentication successful"
    }
    catch {
        Print-Error "Authentication failed: $_"
        exit 1
    }
}

#################################################
# Step 8: Build Docker Sandbox Image
#################################################

function Build-DockerImage {
    Print-Step "Building Docker sandbox image"

    Print-Info "Building openclaw-sandbox image..."
    Print-Info "This may take a few minutes on first run..."

    Push-Location $script:ProxyDir

    try {
        docker build -t openclaw-sandbox -f Dockerfile.sandbox .
        Print-Success "Docker image built successfully"
    }
    catch {
        Print-Error "Docker build failed: $_"
        exit 1
    }

    Pop-Location
}

#################################################
# Step 9: Create OpenClaw Configuration
#################################################

function New-OpenClawConfig {
    Print-Step "Creating OpenClaw configuration"

    # Create directories
    New-Item -ItemType Directory -Path $script:OpenClawDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:WorkspaceDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:LogsDir -Force | Out-Null

    # Create openclaw.json
    $configFile = Join-Path $script:OpenClawDir "openclaw.json"
    Backup-File $configFile

    # Build API keys object
    $apiKeysLines = @("    `"anthropic`": `"`${ANTHROPIC_API_KEY}`"")
    if (-not [string]::IsNullOrWhiteSpace($script:GitHubToken)) {
        $apiKeysLines += "    `"github`": `"`${GITHUB_TOKEN}`""
    }
    if (-not [string]::IsNullOrWhiteSpace($script:OpConnectToken)) {
        $apiKeysLines += "    `"onepassword`": `"`${OP_CONNECT_TOKEN}`""
    }
    $apiKeysJson = $apiKeysLines -join ",`n"

    # Convert Windows paths to JSON-safe format (forward slashes)
    $workspaceDirJson = $script:WorkspaceDir -replace '\\', '/'

    $configContent = @"
{
  "agents": {
    "main": {
      "name": "$script:AgentName",
      "provider": "anthropic",
      "model": "claude-sonnet-4-5",
      "systemPromptFile": "SOUL.md",
      "maxTokens": 8000,
      "sandboxConfig": {
        "type": "docker",
        "image": "openclaw-sandbox",
        "mounts": [
          {
            "type": "bind",
            "source": "$workspaceDirJson",
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
  "workspaceDir": "$workspaceDirJson",
  "apiKeys": {
$apiKeysJson
  },
  "server": {
    "port": 18789,
    "host": "127.0.0.1"
  }
}
"@

    $configContent | Out-File -FilePath $configFile -Encoding utf8
    Print-Success "openclaw.json created"

    # Create .env file
    $envFile = Join-Path $script:OpenClawDir ".env"
    Backup-File $envFile

    $envContent = @"
ANTHROPIC_API_KEY=$script:AnthropicApiKey
"@

    if (-not [string]::IsNullOrWhiteSpace($script:GitHubToken)) {
        $envContent += "`nGITHUB_TOKEN=$script:GitHubToken"
    }

    if (-not [string]::IsNullOrWhiteSpace($script:OpConnectToken)) {
        $envContent += "`nOP_CONNECT_TOKEN=$script:OpConnectToken"
    }

    $envContent | Out-File -FilePath $envFile -Encoding utf8
    Print-Success ".env file created"
}

#################################################
# Step 10: Create Workspace Files
#################################################

function New-WorkspaceFiles {
    Print-Step "Creating workspace files"

    # SOUL.md
    $soulFile = Join-Path $script:WorkspaceDir "SOUL.md"
    Backup-File $soulFile

    @"
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
"@ | Out-File -FilePath $soulFile -Encoding utf8
    Print-Success "SOUL.md created"

    # AGENTS.md
    $agentsFile = Join-Path $script:WorkspaceDir "AGENTS.md"
    Backup-File $agentsFile

    @"
# Agent Configuration

## Main Agent: $script:AgentName
- Provider: Anthropic
- Model: claude-sonnet-4-5
- Sandbox: Docker (openclaw-sandbox)
- Security: Read-only root, no capabilities

## Capabilities
- File system access (workspace only)
- Command execution (sandboxed)
- Network access (via host)
"@ | Out-File -FilePath $agentsFile -Encoding utf8
    Print-Success "AGENTS.md created"

    # USER.md
    $userFile = Join-Path $script:WorkspaceDir "USER.md"
    Backup-File $userFile

    $setupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    @"
# User Context

This file contains information about the user and their preferences.

## User Information
- Setup date: $setupDate
- Primary agent: $script:AgentName
- Platform: Windows

## Preferences
- Communication style: Clear and concise
- Code style: Follow project conventions
- Error handling: Always include proper error handling
"@ | Out-File -FilePath $userFile -Encoding utf8
    Print-Success "USER.md created"

    # HEARTBEAT.md
    $heartbeatFile = Join-Path $script:WorkspaceDir "HEARTBEAT.md"
    Backup-File $heartbeatFile

    @"
# Heartbeat Instructions

This file is read every 30 minutes by the agent to check for tasks and updates.

## Tasks
- Check for system health issues
- Monitor log files for errors
- Check for pending work
- Update status files

## Status
Last check: (Will be updated by agent)
"@ | Out-File -FilePath $heartbeatFile -Encoding utf8
    Print-Success "HEARTBEAT.md created"

    # BOOTSTRAP.md
    $bootstrapFile = Join-Path $script:WorkspaceDir "BOOTSTRAP.md"
    Backup-File $bootstrapFile

    @"
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
"@ | Out-File -FilePath $bootstrapFile -Encoding utf8
    Print-Success "BOOTSTRAP.md created"
}

#################################################
# Step 11: Install Windows Services
#################################################

function Install-WindowsServices {
    Print-Step "Installing Windows Services"

    Print-Info "Installing services via NSSM..."

    # Stop and remove existing services if they exist
    $services = @("VertexAI-Proxy", "OpenClaw-Gateway")
    foreach ($service in $services) {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($svc) {
            Print-Info "Removing existing service: $service"
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            nssm remove $service confirm
        }
    }

    # Install Vertex AI Proxy service
    Print-Info "Installing Vertex AI Proxy service..."
    $pythonPath = Join-Path $script:ProxyDir "venv\Scripts\python.exe"
    $proxyScript = Join-Path $script:ProxyDir "proxy.py"

    nssm install VertexAI-Proxy $pythonPath $proxyScript
    nssm set VertexAI-Proxy AppDirectory $script:ProxyDir
    nssm set VertexAI-Proxy DisplayName "Vertex AI Proxy"
    nssm set VertexAI-Proxy Description "OpenAI-compatible proxy for Google Vertex AI (Gemini)"
    nssm set VertexAI-Proxy Start SERVICE_AUTO_START
    nssm set VertexAI-Proxy AppStdout "$script:LogsDir\vertex-proxy.log"
    nssm set VertexAI-Proxy AppStderr "$script:LogsDir\vertex-proxy.error.log"
    nssm set VertexAI-Proxy AppRotateFiles 1
    nssm set VertexAI-Proxy AppRotateBytes 10485760  # 10MB

    # Set PATH for gcloud
    $gcPath = "$env:ProgramFiles\Google\Cloud SDK\google-cloud-sdk\bin"
    $systemPath = "$env:SystemRoot\system32;$env:SystemRoot"
    $proxyPath = "$gcPath;$systemPath"
    nssm set VertexAI-Proxy AppEnvironmentExtra "PATH=$proxyPath"

    Print-Success "Vertex AI Proxy service installed"

    # Install OpenClaw Gateway service
    Print-Info "Installing OpenClaw Gateway service..."
    $nodePath = (Get-Command node).Source
    $openclawPath = (Get-Command openclaw).Source

    nssm install OpenClaw-Gateway $nodePath $openclawPath gateway start
    nssm set OpenClaw-Gateway AppDirectory $script:OpenClawDir
    nssm set OpenClaw-Gateway DisplayName "OpenClaw Gateway"
    nssm set OpenClaw-Gateway Description "OpenClaw multi-agent AI gateway"
    nssm set OpenClaw-Gateway Start SERVICE_AUTO_START
    nssm set OpenClaw-Gateway AppStdout "$script:LogsDir\gateway.log"
    nssm set OpenClaw-Gateway AppStderr "$script:LogsDir\gateway.error.log"
    nssm set OpenClaw-Gateway AppRotateFiles 1
    nssm set OpenClaw-Gateway AppRotateBytes 10485760  # 10MB

    # Load environment variables from .env
    $envFile = Join-Path $script:OpenClawDir ".env"
    if (Test-Path $envFile) {
        $envVars = Get-Content $envFile | Where-Object { $_ -match '^([^=]+)=(.*)$' } | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                "$($matches[1])=$($matches[2])"
            }
        }
        $envString = $envVars -join "`0"
        nssm set OpenClaw-Gateway AppEnvironmentExtra $envString
    }

    Print-Success "OpenClaw Gateway service installed"
}

#################################################
# Step 12: Start Services
#################################################

function Start-Services {
    Print-Step "Starting services"

    Print-Info "Starting Vertex AI Proxy..."
    try {
        nssm start VertexAI-Proxy
        Print-Success "Vertex AI Proxy started"
    }
    catch {
        Print-Error "Failed to start Vertex AI Proxy: $_"
        exit 1
    }

    Print-Info "Starting OpenClaw Gateway..."
    try {
        nssm start OpenClaw-Gateway
        Print-Success "OpenClaw Gateway started"
    }
    catch {
        Print-Error "Failed to start OpenClaw Gateway: $_"
        exit 1
    }
}

#################################################
# Step 13: Wait for Services
#################################################

function Wait-ForServices {
    Print-Step "Waiting for services to start"

    Print-Info "Waiting for services to initialize..."
    Start-Sleep -Seconds 5

    $maxAttempts = 12

    # Wait for proxy
    Print-Info "Checking Vertex AI Proxy health..."
    $attempt = 0
    $proxyHealthy = $false

    while ($attempt -lt $maxAttempts) {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -UseBasicParsing -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                Print-Success "Vertex AI Proxy is healthy"
                $proxyHealthy = $true
                break
            }
        }
        catch {
            # Ignore errors during startup
        }

        $attempt++
        if ($attempt -eq $maxAttempts) {
            Print-Error "Vertex AI Proxy failed to start"
            Print-Info "Check logs at: $script:LogsDir\vertex-proxy.error.log"
            exit 1
        }
        Start-Sleep -Seconds 2
    }

    # Wait for gateway
    Print-Info "Checking OpenClaw Gateway health..."
    $attempt = 0
    $gatewayHealthy = $false

    while ($attempt -lt $maxAttempts) {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:18789/health" -UseBasicParsing -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                Print-Success "OpenClaw Gateway is healthy"
                $gatewayHealthy = $true
                break
            }
        }
        catch {
            # Ignore errors during startup
        }

        $attempt++
        if ($attempt -eq $maxAttempts) {
            Print-Error "OpenClaw Gateway failed to start"
            Print-Info "Check logs at: $script:LogsDir\gateway.error.log"
            exit 1
        }
        Start-Sleep -Seconds 2
    }
}

#################################################
# Step 14: Run Verification Tests
#################################################

function Test-Installation {
    Print-Step "Running verification tests"

    # Test proxy health
    Print-Info "Testing Vertex AI Proxy..."
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -UseBasicParsing
        $content = $response.Content
        if ($content -match "ok") {
            Print-Success "Proxy health check passed"
        }
        else {
            Print-Warning "Proxy health check returned unexpected response: $content"
        }
    }
    catch {
        Print-Warning "Proxy health check failed: $_"
    }

    # Test gateway health
    Print-Info "Testing OpenClaw Gateway..."
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:18789/health" -UseBasicParsing
        Print-Success "Gateway health check passed"
    }
    catch {
        Print-Warning "Gateway health check failed: $_"
    }

    # Check Docker image
    Print-Info "Verifying Docker sandbox image..."
    try {
        $images = docker images openclaw-sandbox --format "{{.Repository}}"
        if ($images -match "openclaw-sandbox") {
            Print-Success "Docker sandbox image found"
        }
        else {
            Print-Error "Docker sandbox image not found"
        }
    }
    catch {
        Print-Error "Failed to check Docker images: $_"
    }

    # Check workspace files
    Print-Info "Verifying workspace files..."
    $workspaceFiles = @("SOUL.md", "AGENTS.md", "USER.md", "HEARTBEAT.md", "BOOTSTRAP.md")
    foreach ($file in $workspaceFiles) {
        $filePath = Join-Path $script:WorkspaceDir $file
        if (Test-Path $filePath) {
            Print-Success "$file exists"
        }
        else {
            Print-Warning "$file not found"
        }
    }

    # Check service status
    Print-Info "Verifying services..."
    $services = Get-Service -Name "VertexAI-Proxy", "OpenClaw-Gateway" -ErrorAction SilentlyContinue
    foreach ($service in $services) {
        if ($service.Status -eq "Running") {
            Print-Success "$($service.DisplayName) is running"
        }
        else {
            Print-Warning "$($service.DisplayName) is not running (Status: $($service.Status))"
        }
    }
}

#################################################
# Step 15: Print Summary
#################################################

function Show-Summary {
    Print-Step "Setup Complete!"

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "   OpenClaw is ready to use!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""

    Print-Info "Configuration:"
    Write-Host "  * OpenClaw Config: $script:OpenClawDir\openclaw.json"
    Write-Host "  * Workspace: $script:WorkspaceDir"
    Write-Host "  * Logs: $script:LogsDir"
    Write-Host "  * Proxy: http://127.0.0.1:8000"
    Write-Host "  * Gateway: http://127.0.0.1:18789"
    Write-Host ""

    Print-Info "Services:"
    Write-Host "  * Vertex AI Proxy: Running as Windows Service"
    Write-Host "  * OpenClaw Gateway: Running as Windows Service"
    Write-Host ""

    Print-Info "Next Steps:"
    Write-Host ""
    Write-Host "  1. Test the agent:" -ForegroundColor Cyan
    Write-Host "     openclaw chat `"Hello, $script:AgentName!`""
    Write-Host ""
    Write-Host "  2. View logs:" -ForegroundColor Cyan
    Write-Host "     Get-Content $script:LogsDir\vertex-proxy.log -Wait"
    Write-Host "     Get-Content $script:LogsDir\gateway.log -Wait"
    Write-Host ""
    Write-Host "  3. Manage services:" -ForegroundColor Cyan
    Write-Host "     nssm start|stop|restart VertexAI-Proxy"
    Write-Host "     nssm start|stop|restart OpenClaw-Gateway"
    Write-Host ""
    Write-Host "  4. Check service status:" -ForegroundColor Cyan
    Write-Host "     Get-Service VertexAI-Proxy, OpenClaw-Gateway"
    Write-Host ""

    Print-Success "Setup completed successfully!"
    Write-Host ""
}

#################################################
# Main Execution
#################################################

function Main {
    Print-Banner

    Print-Info "This script will set up OpenClaw with Vertex AI Proxy on your Windows machine."
    Print-Info "The process will take 5-10 minutes and requires internet access."
    Write-Host ""

    if (-not (Ask-YesNo "Continue with setup?" "y")) {
        Print-Info "Setup cancelled"
        exit 0
    }

    Test-Administrator
    Test-Prerequisites
    Get-Configuration
    Install-NSSM
    Install-OpenClaw
    Install-VertexProxy
    Initialize-GCloudAuth
    Build-DockerImage
    New-OpenClawConfig
    New-WorkspaceFiles
    Install-WindowsServices
    Start-Services
    Wait-ForServices
    Test-Installation
    Show-Summary
}

# Run main function
try {
    Main
}
catch {
    Print-Error "Setup failed with error: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
