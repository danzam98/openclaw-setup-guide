# OpenClaw Agent Architecture

**Last Updated:** 2026-02-09

## Overview

OpenClaw uses a multi-tier architecture where specialized agents delegate actual work to external CLI tools (Claude Code, Cursor) rather than doing all work with their default Gemini models.

## Architecture Layers

### Layer 1: Main Orchestrator (Steve)
- **Model:** Gemini 2.5 Flash High
- **Purpose:** Coordination, decision-making, task routing
- **Does NOT:** Write code, create plans, or perform detailed work
- **Does:** Spawn specialized agents with explicit instructions

### Layer 2: Specialized Agents
Each agent type has a specific role and uses external CLI tools:

#### Developer Agent
- **Coordination Model:** Gemini (for interpreting tasks and managing workflow)
- **Implementation Tool:** Claude Sonnet 4.5 (via CLI)
- **Review Tool:** Cursor GPT-5.2 (via CLI)
- **Mandatory Skills:** fresh-eyes (after all code changes), bug-hunt, ralph

#### Planner Agent
- **Coordination Model:** Gemini (for task interpretation)
- **Planning Tool:** Claude Opus 4.6 (via CLI)
- **Validation Tool:** Cursor GPT-5.2 (via CLI)
- **Mandatory Skills:** plan-review (2-3 passes), idea-wizard

#### QA-Reviewer Agent
- **Coordination Model:** Gemini
- **Primary Review Tool:** Cursor GPT-5.2 (via CLI)
- **Cross-Validation Tool:** Claude Sonnet 4.5 (via CLI)
- **Skills:** peer-review, bug-hunt, fresh-eyes

#### Researcher Agent
- **Model:** Gemini 2.5 Flash/Pro/Deep Research (direct, no CLI)
- **Skills:** gemini-grounded-research, idea-wizard

### Layer 3: External CLI Tools
Agents invoke external tools via the `bash` tool with specific parameters:

#### Claude Code CLI Invocation
```bash
bash tool with parameters:
  pty: true                    # Pseudo-terminal for interactive CLI
  elevated: true               # Run on host (not in sandbox)
  workdir: ~/path/to/project   # Working directory context
  command: "claude --model sonnet --dangerously-skip-permissions 'task'"
```

#### Cursor CLI Invocation
```bash
bash tool with parameters:
  pty: true
  elevated: true
  workdir: ~/path/to/project
  command: "cursor 'Review task description'"
```

#### Background Mode (Long-Running Tasks)
```bash
bash tool with parameters:
  pty: true
  elevated: true
  workdir: ~/path/to/project
  background: true            # Returns sessionId for monitoring
  command: "claude --model opus 'complex task'"

# Monitor progress:
process action:log sessionId:XXX

# Send follow-up instructions:
process action:submit sessionId:XXX data:"additional instructions"
```

## Task Flow Example

### Simple Feature Implementation

```
1. User → Steve (via Slack/CLI)
   "Implement a login feature"

2. Steve → Developer Agent (spawn)
   Task: """
   Implement login feature with email validation

   IMPORTANT: Use Claude Code CLI for implementation:
   bash pty:true elevated:true workdir:~/project
   command: "claude --model sonnet 'Implement login...'"

   After implementation, use fresh-eyes skill for review.
   """

3. Developer Agent → Claude Sonnet 4.5 (via bash)
   - Reads codebase
   - Writes login code
   - Runs tests
   - Returns results

4. Developer Agent → fresh-eyes skill (via read tool)
   - Reviews all changed code
   - Fixes bugs found
   - Re-runs tests

5. Developer Agent → Steve
   "Feature complete, tests passing, fresh-eyes review done"

6. Steve → User
   "Login feature implemented and reviewed"
```

## Why This Architecture?

### Separation of Concerns
- **Gemini models:** Fast coordination and task interpretation
- **Claude Sonnet/Opus:** Deep reasoning for implementation and planning
- **Cursor:** Code review and validation

### Cost Optimization
- Gemini handles cheap coordination work
- Claude only used for valuable implementation/planning work
- Each model used for its strengths

### Quality Assurance
- Mandatory skills (fresh-eyes, plan-review) enforce quality
- Multi-model validation catches more issues
- Background mode allows for iterative refinement

## Agent SOUL.md Files

Each agent has a SOUL.md file that defines:
1. **Available Tools:** What external CLIs they can invoke
2. **Quality Protocols:** Mandatory skills and when to use them
3. **Decision-Making Guidelines:** When to use which tool
4. **Workflow Patterns:** Concrete examples with bash invocations

### Location
- Main orchestrator: `~/.openclaw/workspace/SOUL.md`
- Specialized agents: `~/.openclaw/agents/{agent-type}/SOUL.md`
- Sandbox (Steve reads from): `~/.openclaw/sandboxes/agent-main-{id}/SOUL.md`

## Skills System

Skills are reusable prompt templates stored in each agent's workspace:

### Developer Skills
- **fresh-eyes** (MANDATORY): Re-read code after changes to catch bugs
- **bug-hunt**: Systematic exploration to find bugs
- **cursor-agent**: Invoke Cursor for code review
- **ralph**: Autonomous multi-step PRD execution

### Planner Skills
- **plan-review** (MANDATORY): Review plans with 2-3 passes until steady state
- **idea-wizard**: Generate 30 ideas, evaluate, present top 5
- **gemini-grounded-research**: Research with Google Search grounding

### QA-Reviewer Skills
- **peer-review**: Structured code review (bugs, security, performance)
- **bug-hunt**: Deep investigation
- **fresh-eyes**: Quick checks

### Researcher Skills
- **gemini-grounded-research**: Current information with web citations
- **idea-wizard**: Brainstorm research directions

## Model Selection Matrix

| Task Type | Coordination | Implementation | Review |
|-----------|-------------|----------------|---------|
| Feature Development | Gemini | Claude Sonnet 4.5 | Cursor GPT-5.2 |
| Planning/PRD | Gemini | Claude Opus 4.6 | Cursor GPT-5.2 |
| Code Review | Gemini | - | Cursor GPT-5.2 |
| Research | Gemini Direct | - | - |
| Bug Investigation | Gemini | Claude Sonnet 4.5 | fresh-eyes skill |

## Configuration Files

### models.json
Location: `~/.openclaw/agents/{agent-type}/agent/models.json`

Only contains Gemini models (for coordination):
```json
{
  "providers": {
    "vertexai-proxy": {
      "baseUrl": "http://127.0.0.1:8000/v1",
      "models": [
        {"id": "google/gemini-2.5-flash-low"},
        {"id": "google/gemini-2.5-flash-medium"},
        {"id": "google/gemini-2.5-flash-high"}
      ]
    }
  }
}
```

Claude/Cursor are accessed via CLI, not via models.json.

### CURSOR-USAGE.md
Location: `~/.openclaw/workspace/CURSOR-USAGE.md`

Documents how to invoke Cursor and Claude Code CLIs from agents.

## Troubleshooting

### Agent Not Using Claude CLI
**Symptom:** Agent uses Gemini for everything, never invokes Claude CLI

**Cause:** Steve's SOUL.md or agent's SOUL.md missing bash invocation instructions

**Fix:** Ensure Steve's task prompt includes explicit bash parameters:
```
bash pty:true elevated:true workdir:~/project
command: "claude --model sonnet 'task'"
```

### CLI Command Hangs
**Symptom:** Bash command never returns

**Cause:** Missing `pty:true` parameter

**Fix:** Always include `pty:true` for interactive CLIs

### Permission Denied
**Symptom:** CLI command fails with permission error

**Cause:** Missing `elevated:true` parameter

**Fix:** Include `elevated:true` to run on host (where CLIs are installed)

## References

- OpenClaw Config Repo: https://github.com/danzam98/openclaw-config
- Commit 9127a80: Added skill usage instructions
- Commit cd726eb: Added explicit bash CLI invocation patterns
