# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-09

### Added

#### Documentation
- Comprehensive README.md with architecture diagram, setup instructions, and troubleshooting
- FOR-CLAUDE.md mechanical setup checklist for AI agent assistance
- CONTRIBUTING.md with guidelines for contributors
- Complete MIT LICENSE

#### Setup Scripts
- **setup-mac.sh** - Automated macOS setup with Homebrew integration
- **setup-windows.ps1** - Automated Windows setup with winget and NSSM integration
- Both scripts are idempotent and include comprehensive error handling

#### Templates
- `openclaw.json.template` - Complete OpenClaw configuration with 7 agents
- `Dockerfile.sandbox-dev` - Secure Docker sandbox with all development tools
- macOS LaunchD plists for both services (with PATH fix)
- Windows NSSM service installation script
- Workspace files: SOUL.md, AGENTS.md, BOOTSTRAP.md
- User customization templates: USER.md, HEARTBEAT.md

#### Features
- Multi-agent orchestration (Main, Planner, Developer, Researcher, QA-Reviewer, DevOps, Image Generator)
- Vertex AI Proxy with streaming support
- Docker sandbox isolation with security hardening
- Slack integration with Socket Mode
- Heartbeat-based proactive agent behavior
- Memory system with QMD backend
- Custom skills support

### Documentation Highlights

#### Troubleshooting Coverage
- LaunchD PATH issues preventing gcloud access
- Vertex AI proxy streaming requirements
- GOOGLE_APPLICATION_CREDENTIALS conflicts
- Workspace file synchronization gotchas
- Service restart requirements after code changes
- Docker permission errors

#### Cost Transparency
- Detailed Gemini API pricing breakdown
- Heartbeat cost calculation (~$0.65/day)
- Usage examples for different workloads
- Cost optimization tips

#### Security
- Docker isolation details (read-only root, dropped capabilities)
- Secrets management with 1Password integration
- Slack security configuration
- Network security recommendations

### Known Limitations

- Vertex AI Proxy currently supports Gemini 2.5 Flash only
- 1Password integration is optional (manual .env setup also supported)
- Skills system requires manual file placement
- Service restart required after proxy code changes

### Testing

- macOS setup tested on macOS 13+ (Ventura)
- Windows setup designed for Windows 10/11
- All templates validated against working production system

---

## How to Update This Changelog

When contributing changes:

1. Add new entries under `[Unreleased]` section
2. Use categories: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`
3. Include issue/PR numbers where applicable
4. Update version and date when releasing

Example:
```markdown
## [Unreleased]

### Added
- Support for Claude Opus 4.6 model (#123)

### Fixed
- Docker build failure on ARM64 systems (#124)
```
