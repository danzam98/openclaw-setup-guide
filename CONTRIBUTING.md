# Contributing to OpenClaw Setup Guide

Thank you for your interest in improving this setup guide! This document provides guidelines for contributing.

## How to Contribute

### Reporting Issues

If you encounter problems during setup:

1. **Check existing issues** to see if it's already reported
2. **Provide detailed information**:
   - Operating system and version
   - Step where the issue occurred
   - Full error messages (redact any tokens/secrets)
   - What you've tried to fix it

### Suggesting Improvements

Have an idea to make setup easier?

1. Open an issue describing your suggestion
2. Explain the problem it solves
3. Provide example implementation if possible

### Submitting Changes

#### For Documentation Fixes

1. Fork the repository
2. Make your changes
3. Test the documentation for clarity
4. Submit a pull request with:
   - Clear description of what changed
   - Why the change improves the guide

#### For Script Changes

1. Fork the repository
2. Make your changes to `setup-mac.sh` or `setup-windows.ps1`
3. **Test on a clean system** (VM recommended)
4. Ensure idempotency (safe to run multiple times)
5. Update relevant documentation
6. Submit a pull request with:
   - Description of the change
   - Testing methodology
   - Example output

#### For Template Changes

1. Update the template file in `templates/`
2. Test the template generates valid configuration
3. Update `README.md` and `FOR-CLAUDE.md` if needed
4. Submit a pull request

## Code Style

### Shell Scripts (Bash)
- Use 4-space indentation
- Include comments for complex logic
- Use `set -e` for error handling
- Colorize output for better UX
- Test with `shellcheck`

### PowerShell Scripts
- Follow PowerShell best practices
- Use approved verbs for functions
- Include error handling
- Test on Windows 10 and 11

### Documentation (Markdown)
- Use clear, concise language
- Include code blocks with syntax highlighting
- Add warnings for critical steps
- Keep line length reasonable (80-100 chars)

## Security Guidelines

**CRITICAL:** Never commit sensitive information:

- API keys or tokens
- Service account credentials
- Personal email addresses
- Project IDs
- Any `xoxb-`, `xapp-`, `AIza`, `ops_`, or similar tokens

Before submitting:
1. Review your changes for secrets
2. Use placeholder values like `{{VARIABLE}}`
3. Check with: `git diff | grep -i "token\|key\|secret\|password"`

## Testing Requirements

### For Setup Scripts

Test on a **clean system** (recommended: fresh VM):

1. **macOS Testing:**
   - Test on macOS 13+ (Ventura or newer)
   - Verify Homebrew integration
   - Check LaunchD service creation
   - Confirm all steps complete successfully

2. **Windows Testing:**
   - Test on Windows 10/11
   - Verify winget integration
   - Check NSSM service installation
   - Confirm PowerShell execution policy handling

### For Documentation

1. Follow the guide yourself from start to finish
2. Note any unclear steps
3. Verify all commands work as documented
4. Check external links are valid

## Documentation Structure

When updating documentation, maintain consistency:

- **README.md** - Human-readable guide
- **FOR-CLAUDE.md** - Mechanical checklist for AI agents
- Keep both in sync when changing steps
- Update troubleshooting sections with new issues

## Pull Request Process

1. **Create a descriptive PR title**
   - Good: "Fix LaunchD PATH issue in macOS setup"
   - Bad: "Update script"

2. **Provide context in PR description**
   - What problem does this solve?
   - How did you test it?
   - Any breaking changes?

3. **Keep PRs focused**
   - One feature/fix per PR
   - Separate formatting changes from logic changes

4. **Respond to feedback**
   - Address review comments
   - Update based on suggestions
   - Be open to discussion

## Questions?

Open an issue with the `question` label. We're happy to help!

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
