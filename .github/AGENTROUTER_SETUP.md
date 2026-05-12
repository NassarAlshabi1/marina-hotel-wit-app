# 🤖 Claude Code + AgentRouter Setup Guide

## 📋 Overview

This repository is configured to use Claude Code with AgentRouter for AI-powered GitHub Actions.

---

## 🔑 Step 1: Add API Key to GitHub Secrets

**IMPORTANT: Never commit API keys directly to the repository!**

### Method 1: GitHub Web Interface

1. Go to your repository on GitHub
2. Navigate to: **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Enter:
   - **Name**: `AGENTROUTER_API_KEY`
   - **Value**: Your AgentRouter API key (starts with `sk-`)
5. Click **Add secret**

### Method 2: GitHub CLI

```bash
gh secret set AGENTROUTER_API_KEY
# Paste your API key and press Enter
```

---

## 🚀 Available Workflows

### 1. Claude Code Main (`claude-agentrouter.yml`)
**Trigger**: Mention `@claude` in issues, PR comments, or PR reviews

**Usage**:
- Comment `@claude` on any issue or PR
- Claude will respond and help with the task

### 2. Issue Triage (`claude-issue-triage.yml`)
**Trigger**: New issue opened

**Features**:
- Automatically analyzes new issues
- Adds appropriate labels (bug, enhancement, question, etc.)
- Prioritizes issues

### 3. Code Review (`claude-code-review.yml`)
**Trigger**: Pull request opened or updated

**Features**:
- Reviews code changes
- Detects bugs and security issues
- Suggests improvements
- Posts review comments

---

## 💻 Local Development Setup

### Environment Variables

```bash
export ANTHROPIC_BASE_URL="https://agentrouter.org/"
export ANTHROPIC_API_KEY="sk-your-api-key-here"
export ANTHROPIC_AUTH_TOKEN="sk-your-api-key-here"
```

### Run Claude Code Locally

```bash
# Install Claude Code
npm install -g @anthropic-ai/claude-code

# Run Claude
claude
```

---

## 🎯 Usage Examples

### In Issues

```
@claude can you help me fix the authentication bug?
```

### In Pull Requests

```
@claude please review this code for security issues
```

---

## 📊 Available Models via AgentRouter

| Model | Use Case |
|-------|----------|
| `claude-sonnet-4-5-20250929` | Main coding tasks |
| `claude-haiku-4-5-20251001` | Fast, simple tasks |

---

## 🔧 Changing Models

Edit the `claude_args` in any workflow file:

```yaml
claude_args: "--model claude-sonnet-4-5-20250929"
```

---

## ⚠️ Security Notes

1. **Never commit API keys** to the repository
2. **Regenerate your key** if accidentally exposed
3. **Use GitHub Secrets** for all sensitive data

---

## 📚 Resources

- [AgentRouter Console](https://agentrouter.org/console/token)
- [AgentRouter Docs](https://docs.agentrouter.org/en)
- [Claude Code Docs](https://docs.anthropic.com/claude-code)
