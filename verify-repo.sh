#!/bin/bash
# Repository verification script
# Run this before publishing to ensure everything is ready

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 OpenClaw Setup Guide - Repository Verification"
echo "=================================================="
echo ""

ERRORS=0
WARNINGS=0

# Check all required files exist
echo "📁 Checking required files..."
REQUIRED_FILES=(
    "README.md"
    "FOR-CLAUDE.md"
    "setup-mac.sh"
    "setup-windows.ps1"
    "LICENSE"
    "CHANGELOG.md"
    "CONTRIBUTING.md"
    ".gitignore"
    "templates/openclaw.json.template"
    "templates/Dockerfile.sandbox-dev"
    "templates/workspace/SOUL.md"
    "templates/workspace/AGENTS.md"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $file"
    else
        echo -e "${RED}✗${NC} $file (MISSING)"
        ((ERRORS++))
    fi
done
echo ""

# Check for secrets
echo "🔐 Scanning for potential secrets..."
PATTERNS=(
    "xoxb-[0-9]"           # Real Slack bot tokens
    "xapp-[0-9]"           # Real Slack app tokens
    "AIza[A-Za-z0-9_-]{35}" # Real Google API keys
    "ops_eyJ"              # 1Password service account tokens
    "AKIA[0-9A-Z]{16}"     # AWS access keys
)

SECRET_FOUND=0
for pattern in "${PATTERNS[@]}"; do
    if grep -rE "$pattern" --include="*.md" --include="*.sh" --include="*.ps1" --include="*.json" --include="*.plist" . 2>/dev/null | grep -v "\.git/" | grep -v "verify-repo.sh"; then
        echo -e "${RED}✗ Found potential secret matching: $pattern${NC}"
        ((ERRORS++))
        SECRET_FOUND=1
    fi
done

if [ $SECRET_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ No secrets detected${NC}"
fi
echo ""

# Check for personal information
echo "👤 Checking for personal information..."
PERSONAL_PATTERNS=(
    "calicospanish.1password.com"
    "@calicospanish"
    "501:20"  # Specific user:group ID
)

PERSONAL_FOUND=0
for pattern in "${PERSONAL_PATTERNS[@]}"; do
    if grep -r "$pattern" --include="*.md" --include="*.sh" --include="*.ps1" --include="*.json" --include="*.plist" . 2>/dev/null | grep -v "\.git/" | grep -v "verify-repo.sh"; then
        echo -e "${YELLOW}⚠${NC}  Found personal reference: $pattern"
        ((WARNINGS++))
        PERSONAL_FOUND=1
    fi
done

if [ $PERSONAL_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ No personal information detected${NC}"
fi
echo ""

# Verify executables
echo "⚙️  Checking executable permissions..."
if [ -x "setup-mac.sh" ]; then
    echo -e "${GREEN}✓${NC} setup-mac.sh is executable"
else
    echo -e "${RED}✗${NC} setup-mac.sh is NOT executable (run: chmod +x setup-mac.sh)"
    ((ERRORS++))
fi
echo ""

# Check shell script syntax
echo "🔧 Validating shell scripts..."
if command -v shellcheck &> /dev/null; then
    if shellcheck setup-mac.sh; then
        echo -e "${GREEN}✓${NC} setup-mac.sh passes shellcheck"
    else
        echo -e "${YELLOW}⚠${NC}  setup-mac.sh has shellcheck warnings"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}⚠${NC}  shellcheck not installed (optional: brew install shellcheck)"
fi
echo ""

# Verify git status
echo "📦 Checking git repository..."
if [ -d ".git" ]; then
    echo -e "${GREEN}✓${NC} Git repository initialized"

    # Check for uncommitted changes
    if [ -z "$(git status --porcelain)" ]; then
        echo -e "${GREEN}✓${NC} No uncommitted changes"
    else
        echo -e "${YELLOW}⚠${NC}  Uncommitted changes detected:"
        git status --short
        ((WARNINGS++))
    fi

    # Check commit count
    COMMIT_COUNT=$(git rev-list --count HEAD)
    echo -e "${GREEN}✓${NC} Repository has $COMMIT_COUNT commit(s)"
else
    echo -e "${RED}✗${NC} Not a git repository"
    ((ERRORS++))
fi
echo ""

# Verify template variables
echo "🎯 Checking template variable consistency..."
TEMPLATE_VARS=(
    "{{GCP_PROJECT_ID}}"
    "{{GCP_REGION}}"
    "{{SLACK_BOT_TOKEN}}"
    "{{SLACK_APP_TOKEN}}"
    "{{GEMINI_API_KEY}}"
    "{{HOME}}"
    "{{AGENT_NAME}}"
)

for var in "${TEMPLATE_VARS[@]}"; do
    if grep -rq "$var" --include="*.template" --include="*.md" templates/; then
        echo -e "${GREEN}✓${NC} $var found in templates"
    else
        echo -e "${YELLOW}⚠${NC}  $var not found (may not be used)"
    fi
done
echo ""

# Check documentation completeness
echo "📚 Verifying documentation..."
REQUIRED_SECTIONS=(
    "Architecture"
    "Prerequisites"
    "Quick Start"
    "Manual Setup"
    "Troubleshooting"
    "Security"
)

for section in "${REQUIRED_SECTIONS[@]}"; do
    if grep -q "$section" README.md; then
        echo -e "${GREEN}✓${NC} README.md has '$section' section"
    else
        echo -e "${RED}✗${NC} README.md missing '$section' section"
        ((ERRORS++))
    fi
done
echo ""

# Summary
echo "=================================================="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Repository is ready for publication.${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found. Review and fix if needed.${NC}"
    exit 0
else
    echo -e "${RED}✗ $ERRORS error(s) and $WARNINGS warning(s) found. Fix before publishing.${NC}"
    exit 1
fi
