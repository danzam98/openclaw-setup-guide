# OpenClaw Windows Service Installation Script
# Run this script as Administrator after completing manual setup

param(
    [Parameter(Mandatory=$true)]
    [string]$VertexAIProxyPath,

    [Parameter(Mandatory=$true)]
    [string]$OpenClawPath
)

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    exit 1
}

# Check if NSSM is installed
if (-not (Get-Command nssm -ErrorAction SilentlyContinue)) {
    Write-Host "Installing NSSM (Non-Sucking Service Manager)..." -ForegroundColor Yellow
    winget install nssm
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to install NSSM" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Installing OpenClaw services..." -ForegroundColor Green

# Stop and remove existing services if they exist
$services = @("VertexAI-Proxy", "OpenClaw-Gateway")
foreach ($service in $services) {
    if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
        Write-Host "Removing existing service: $service" -ForegroundColor Yellow
        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        nssm remove $service confirm
    }
}

# Install Vertex AI Proxy service
Write-Host "Installing Vertex AI Proxy service..." -ForegroundColor Cyan
$pythonPath = Join-Path $VertexAIProxyPath "venv\Scripts\python.exe"
$proxyScript = Join-Path $VertexAIProxyPath "proxy.py"

nssm install VertexAI-Proxy $pythonPath $proxyScript
nssm set VertexAI-Proxy AppDirectory $VertexAIProxyPath
nssm set VertexAI-Proxy DisplayName "Vertex AI Proxy"
nssm set VertexAI-Proxy Description "OpenAI-compatible proxy for Google Vertex AI (Gemini)"
nssm set VertexAI-Proxy Start SERVICE_AUTO_START
nssm set VertexAI-Proxy AppStdout "$env:TEMP\vertexai-proxy.log"
nssm set VertexAI-Proxy AppStderr "$env:TEMP\vertexai-proxy.err.log"
nssm set VertexAI-Proxy AppRotateFiles 1
nssm set VertexAI-Proxy AppRotateBytes 10485760  # 10MB

# Set PATH environment variable for Vertex AI Proxy
$proxyPath = "$env:ProgramFiles\Google\Cloud SDK\google-cloud-sdk\bin;$env:SystemRoot\system32;$env:SystemRoot"
nssm set VertexAI-Proxy AppEnvironmentExtra "PATH=$proxyPath"

Write-Host "Starting Vertex AI Proxy service..." -ForegroundColor Cyan
nssm start VertexAI-Proxy

# Install OpenClaw Gateway service
Write-Host "Installing OpenClaw Gateway service..." -ForegroundColor Cyan
$nodePath = (Get-Command node).Source
$openclawScript = $OpenClawPath

# Load environment variables from .env
$envPath = "$env:USERPROFILE\.openclaw\.env"
if (Test-Path $envPath) {
    $envVars = Get-Content $envPath | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            "$($matches[1])=$($matches[2])"
        }
    }
    $envString = $envVars -join "`0"
} else {
    Write-Host "WARNING: .env file not found at $envPath" -ForegroundColor Yellow
    $envString = ""
}

nssm install OpenClaw-Gateway $nodePath $openclawScript gateway --port 18789
nssm set OpenClaw-Gateway AppDirectory "$env:USERPROFILE\.openclaw"
nssm set OpenClaw-Gateway DisplayName "OpenClaw Gateway"
nssm set OpenClaw-Gateway Description "OpenClaw multi-agent AI gateway"
nssm set OpenClaw-Gateway Start SERVICE_AUTO_START
nssm set OpenClaw-Gateway AppStdout "$env:USERPROFILE\.openclaw\logs\gateway.log"
nssm set OpenClaw-Gateway AppStderr "$env:USERPROFILE\.openclaw\logs\gateway.err.log"
nssm set OpenClaw-Gateway AppRotateFiles 1
nssm set OpenClaw-Gateway AppRotateBytes 10485760  # 10MB

# Set environment variables for OpenClaw Gateway
if ($envString) {
    nssm set OpenClaw-Gateway AppEnvironmentExtra $envString
}

Write-Host "Starting OpenClaw Gateway service..." -ForegroundColor Cyan
nssm start OpenClaw-Gateway

# Verify services are running
Start-Sleep -Seconds 5

Write-Host "`nService Status:" -ForegroundColor Green
Get-Service -Name "VertexAI-Proxy", "OpenClaw-Gateway" | Format-Table -AutoSize

Write-Host "`nServices installed and started successfully!" -ForegroundColor Green
Write-Host "Check logs at:" -ForegroundColor Cyan
Write-Host "  - Vertex AI Proxy: $env:TEMP\vertexai-proxy.log" -ForegroundColor White
Write-Host "  - OpenClaw Gateway: $env:USERPROFILE\.openclaw\logs\gateway.log" -ForegroundColor White

Write-Host "`nTo manage services, use:" -ForegroundColor Cyan
Write-Host "  nssm start|stop|restart VertexAI-Proxy" -ForegroundColor White
Write-Host "  nssm start|stop|restart OpenClaw-Gateway" -ForegroundColor White
