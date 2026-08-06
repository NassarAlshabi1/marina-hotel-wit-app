#!/usr/bin/env node
/**
 * ═══════════════════════════════════════════════════════════════
 *  ai-code-review.mjs — AI Code Review Bot using Z AI API
 *  ═══════════════════════════════════════════════════════════════
 * 
 *  يحلل تغييرات Git (diff) ويراقب الأخطاء واقتراح إصلاحات
 *  باستخدام نموذج GLM-4-Plus من Z AI.
 * 
 *  الاستخدام:
 *    node ai-code-review.mjs                    # فحص تغييرات PR الحالي
 *    node ai-code-review.mjs --base main        # مقارنة مع فرع محدد
 *    node ai-code-review.mjs --files a.dart b.dart  # فحص ملفات محددة
 *    node ai-code-review.mjs --comment          # إضافة تعليق على PR
 *    node ai-code-review.mjs --format json      # إخراج JSON
 *    node ai-code-review.mjs --model glm-4-flash  # نموذج محدد
 * 
 *  Environment:
 *    ZAI_API_KEY   — Z AI API key (مطلوب)
 *    GITHUB_TOKEN  — GitHub token (للتعليق على PR)
 *    GITHUB_REPOSITORY — owner/repo (يُضبط تلقائياً في CI)
 *    GITHUB_PR_NUMBER — رقم PR (يُضبط تلقائياً في CI)
 * ═══════════════════════════════════════════════════════════════
 */

import { execSync } from 'child_process';
import { readFileSync, existsSync } from 'fs';

// ─── Configuration ────────────────────────────────────────────

const API_KEY = process.env.ZAI_API_KEY || '';
const API_URL = 'https://api.z.ai/api/paas/v4/chat/completions';
const GITHUB_TOKEN = process.env.GITHUB_TOKEN || '';
const GITHUB_REPOSITORY = process.env.GITHUB_REPOSITORY || '';
const GITHUB_PR_NUMBER = process.env.GITHUB_PR_NUMBER || '';

// Parse CLI args
const args = process.argv.slice(2);
const opts = {
  base: 'origin/main',
  files: [],
  comment: false,
  format: 'terminal',
  model: 'glm-4-plus',
  maxFiles: 20,
  maxLinesPerFile: 500,
  maxDiffSize: 50000,
};

for (let i = 0; i < args.length; i++) {
  switch (args[i]) {
    case '--base': opts.base = args[++i]; break;
    case '--files': opts.files = args.slice(i + 1); i = args.length; break;
    case '--comment': opts.comment = true; break;
    case '--format': opts.format = args[++i]; break;
    case '--model': opts.model = args[++i]; break;
    case '--max-files': opts.maxFiles = parseInt(args[++i]); break;
    case '--help':
      console.log(`AI Code Review Bot (Z AI + GLM-4)

Usage: node ai-code-review.mjs [options]

Options:
  --base <branch>        Base branch for diff (default: origin/main)
  --files <f1> <f2>...   Specific files to review
  --comment              Post review as GitHub PR comment
  --format <fmt>         Output: terminal, json, markdown (default: terminal)
  --model <model>        Z AI model (default: glm-4-plus)
  --max-files <n>        Max files to review (default: 20)

Environment:
  ZAI_API_KEY            Z AI API key (required)
  GITHUB_TOKEN           GitHub token (for --comment)
  GITHUB_REPOSITORY      owner/repo (auto in CI)
  GITHUB_PR_NUMBER       PR number (auto in CI)`);
      process.exit(0);
  }
}

// ─── Colors ───────────────────────────────────────────────────

const C = {
  red: '\x1b[31m', green: '\x1b[32m', yellow: '\x1b[33m',
  blue: '\x1b[34m', purple: '\x1b[35m', cyan: '\x1b[36m',
  bold: '\x1b[1m', dim: '\x1b[2m', reset: '\x1b[0m',
};

// ─── Git Helpers ──────────────────────────────────────────────

function getDiff(base = opts.base) {
  try {
    // Get list of changed files
    const filesRaw = execSync(
      `git diff --name-only --diff-filter=ACMR ${base}...HEAD 2>/dev/null || git diff --name-only --diff-filter=ACMR HEAD~1 2>/dev/null || echo ""`,
      { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 }
    ).trim();
    
    if (!filesRaw) return { files: [], diffs: [] };
    
    let files = filesRaw.split('\n').filter(f => f.trim());
    
    // Filter to code files only
    files = files.filter(f => 
      /\.(dart|ts|js|py|java|kt|go|rs|rb|php|swift|c|cpp|h|cs)$/i.test(f) &&
      !f.includes('.g.dart') &&
      !f.includes('.freezed.dart') &&
      !f.includes('node_modules') &&
      !f.includes('build/')
    );
    
    // Limit number of files
    if (files.length > opts.maxFiles) {
      console.log(`${C.yellow}⚠ ${files.length} files changed, reviewing first ${opts.maxFiles}${C.reset}`);
      files = files.slice(0, opts.maxFiles);
    }
    
    // Get diff for each file
    const diffs = [];
    for (const file of files) {
      try {
        const diff = execSync(
          `git diff ${base}...HEAD -- "${file}" 2>/dev/null || git diff HEAD~1 -- "${file}" 2>/dev/null || echo ""`,
          { encoding: 'utf8', maxBuffer: 5 * 1024 * 1024 }
        ).trim();
        
        if (diff && diff.length < opts.maxDiffSize) {
          // Truncate very large diffs
          const truncated = diff.length > opts.maxLinesPerFile * 50
            ? diff.slice(0, opts.maxLinesPerFile * 50) + '\n... (truncated)'
            : diff;
          diffs.push({ file, diff: truncated });
        }
      } catch (e) {
        // Skip files that can't be diffed
      }
    }
    
    return { files, diffs };
  } catch (e) {
    return { files: [], diffs: [] };
  }
}

function getSpecificFiles(fileList) {
  const diffs = [];
  for (const file of fileList) {
    if (!existsSync(file)) continue;
    try {
      const content = readFileSync(file, 'utf8');
      const lines = content.split('\n').slice(0, opts.maxLinesPerFile);
      diffs.push({
        file,
        diff: `--- ${file} (full content, first ${opts.maxLinesPerFile} lines)\n+++ ${file}\n${lines.map(l => `+${l}`).join('\n')}`,
      });
    } catch (e) {
      // Skip
    }
  }
  return { files: fileList, diffs };
}

// ─── Z AI API Call ────────────────────────────────────────────

async function reviewWithAI(diffs) {
  if (!API_KEY) {
    throw new Error('ZAI_API_KEY environment variable is required');
  }
  
  if (diffs.length === 0) {
    return { issues: [], summary: 'No changes to review.' };
  }
  
  // Build the review prompt
  const codeBlocks = diffs.map(d => 
    `### File: ${d.file}\n\`\`\`diff\n${d.diff}\n\`\`\``
  ).join('\n\n');
  
  const systemPrompt = `You are an expert code reviewer for a production hotel management system (Flutter/Dart + Cloudflare Worker + TypeScript).
Your job is to find REAL bugs, security issues, data loss risks, and performance problems.

Focus on:
1. 🔴 CRITICAL: Data loss, race conditions, security vulnerabilities, financial calculation errors
2. 🟠 HIGH: Null safety issues, unhandled exceptions, resource leaks, missing error handling
3. 🟡 MEDIUM: Performance issues, code smell, missing edge cases, API misuse
4. 🔵 LOW: Style issues, documentation gaps, minor improvements

For each issue, provide:
- severity: CRITICAL | HIGH | MEDIUM | LOW
- file: filename
- line: approximate line number (or "unknown")
- category: bug | security | performance | style | logic
- message: what's wrong (in Arabic + English)
- suggestion: how to fix it (code snippet if possible)

Respond as JSON array. If no issues found, return empty array [].
Only report REAL issues — do not report false positives or style preferences.`;

  const userPrompt = `Review the following code changes from a Git diff.
This is a hotel management system with financial data (payments, bookings, salaries).
Be strict about data integrity and financial accuracy.

Changed files (${diffs.length}):
${diffs.map(d => `- ${d.file}`).join('\n')}

Diffs:
${codeBlocks}`;

  console.log(`${C.cyan}🤖 Sending ${diffs.length} files to ${opts.model}...${C.reset}`);
  
  const response = await fetch(API_URL, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: opts.model,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt },
      ],
      temperature: 0.1,
      max_tokens: 4000,
    }),
  });
  
  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Z AI API error ${response.status}: ${errText}`);
  }
  
  const data = await response.json();
  const content = data.choices?.[0]?.message?.content || '[]';
  
  // Parse JSON from response (handle markdown code blocks)
  let jsonStr = content.trim();
  if (jsonStr.startsWith('```json')) {
    jsonStr = jsonStr.slice(7);
  }
  if (jsonStr.startsWith('```')) {
    jsonStr = jsonStr.slice(3);
  }
  if (jsonStr.endsWith('```')) {
    jsonStr = jsonStr.slice(0, -3);
  }
  jsonStr = jsonStr.trim();
  
  let issues = [];
  try {
    issues = JSON.parse(jsonStr);
    if (!Array.isArray(issues)) issues = [issues];
  } catch (e) {
    // If JSON parsing fails, treat the whole response as a single issue
    issues = [{
      severity: 'INFO',
      file: 'general',
      line: 'unknown',
      category: 'review',
      message: content.slice(0, 500),
      suggestion: 'See full AI response above.',
    }];
  }
  
  return {
    issues,
    summary: `Reviewed ${diffs.length} files, found ${issues.length} issue(s).`,
    usage: data.usage,
  };
}

// ─── Output Formatters ────────────────────────────────────────

const SEVERITY_CONFIG = {
  CRITICAL: { icon: '🔴', color: C.red, weight: 4 },
  HIGH:     { icon: '🟠', color: '\x1b[38;5;208m', weight: 3 },
  MEDIUM:   { icon: '🟡', color: C.yellow, weight: 2 },
  LOW:      { icon: '🔵', color: C.blue, weight: 1 },
  INFO:     { icon: 'ℹ️',  color: C.cyan, weight: 0 },
};

function formatTerminal(result) {
  const { issues, summary, usage } = result;
  
  console.log('\n' + '═'.repeat(70));
  console.log(`${C.bold}  🤖 AI Code Review Report${C.reset}`);
  console.log('═'.repeat(70));
  console.log(`  ${C.dim}${summary}${C.reset}`);
  if (usage) {
    console.log(`  ${C.dim}Tokens: ${usage.total_tokens} (prompt: ${usage.prompt_tokens}, completion: ${usage.completion_tokens})${C.reset}`);
  }
  console.log('');
  
  if (issues.length === 0) {
    console.log(`  ${C.green}✅ No issues found! Code looks good.${C.reset}\n`);
    return;
  }
  
  // Sort by severity
  issues.sort((a, b) => 
    (SEVERITY_CONFIG[b.severity]?.weight || 0) - (SEVERITY_CONFIG[a.severity]?.weight || 0)
  );
  
  for (const issue of issues) {
    const cfg = SEVERITY_CONFIG[issue.severity] || SEVERITY_CONFIG.INFO;
    console.log(`  ${cfg.icon} ${cfg.color}${C.bold}[${issue.severity}]${C.reset} ${cfg.color}${issue.category || 'review'}${C.reset}`);
    console.log(`    ${C.dim}📄 ${issue.file}:${issue.line || '?'}${C.reset}`);
    console.log(`    ${issue.message}`);
    if (issue.suggestion) {
      console.log(`    ${C.green}💡 ${issue.suggestion}${C.reset}`);
    }
    console.log('');
  }
  
  // Summary stats
  const counts = {};
  for (const i of issues) {
    counts[i.severity] = (counts[i.severity] || 0) + 1;
  }
  console.log('─'.repeat(70));
  console.log(`  ${C.bold}Summary:${C.reset} ${issues.length} issue(s) — ` +
    Object.entries(counts).map(([k, v]) => `${SEVERITY_CONFIG[k]?.icon || '•'} ${k}: ${v}`).join(' | '));
  console.log('');
}

function formatMarkdown(result) {
  const { issues, summary, usage } = result;
  
  let md = `## 🤖 AI Code Review Report\n\n`;
  md += `${summary}\n`;
  if (usage) {
    md += `*Tokens: ${usage.total_tokens} (prompt: ${usage.prompt_tokens}, completion: ${usage.completion_tokens})*\n`;
  }
  md += `\n`;
  
  if (issues.length === 0) {
    md += `✅ **No issues found! Code looks good.**\n`;
    return md;
  }
  
  // Sort by severity
  issues.sort((a, b) => 
    (SEVERITY_CONFIG[b.severity]?.weight || 0) - (SEVERITY_CONFIG[a.severity]?.weight || 0)
  );
  
  // Summary table
  md += `| Severity | Count |\n|---|---|\n`;
  const counts = {};
  for (const i of issues) counts[i.severity] = (counts[i.severity] || 0) + 1;
  for (const [k, v] of Object.entries(counts)) {
    md += `| ${SEVERITY_CONFIG[k]?.icon || '•'} ${k} | ${v} |\n`;
  }
  md += `\n`;
  
  // Issues detail
  for (const issue of issues) {
    const cfg = SEVERITY_CONFIG[issue.severity] || SEVERITY_CONFIG.INFO;
    md += `### ${cfg.icon} [${issue.severity}] ${issue.category || 'review'}\n`;
    md += `**File:** \`${issue.file}:${issue.line || '?'}\`\n\n`;
    md += `${issue.message}\n\n`;
    if (issue.suggestion) {
      md += `**💡 Suggestion:**\n\`\`\`\n${issue.suggestion}\n\`\`\`\n\n`;
    }
  }
  
  return md;
}

function formatJSON(result) {
  console.log(JSON.stringify(result, null, 2));
}

// ─── GitHub PR Comment ────────────────────────────────────────

async function postPRComment(markdown) {
  if (!GITHUB_TOKEN || !GITHUB_REPOSITORY || !GITHUB_PR_NUMBER) {
    console.log(`${C.yellow}⚠ Missing GitHub env vars — skipping PR comment${C.reset}`);
    return false;
  }
  
  const url = `https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${GITHUB_PR_NUMBER}/comments`;
  
  // Check if there's an existing comment from this bot
  const existingResponse = await fetch(url, {
    headers: {
      'Authorization': `token ${GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github+json',
    },
  });
  
  if (existingResponse.ok) {
    const comments = await existingResponse.json();
    const botComment = comments.find(c => 
      c.user.type === 'Bot' && c.body.includes('🤖 AI Code Review Report')
    );
    
    if (botComment) {
      // Update existing comment
      const updateUrl = `https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/comments/${botComment.id}`;
      const updateResponse = await fetch(updateUrl, {
        method: 'PATCH',
        headers: {
          'Authorization': `token ${GITHUB_TOKEN}`,
          'Accept': 'application/vnd.github+json',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ body: markdown }),
      });
      
      if (updateResponse.ok) {
        console.log(`${C.green}✅ Updated existing PR comment${C.reset}`);
        return true;
      }
    }
  }
  
  // Create new comment
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `token ${GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ body: markdown }),
  });
  
  if (response.ok) {
    console.log(`${C.green}✅ Posted PR comment #${GITHUB_PR_NUMBER}${C.reset}`);
    return true;
  } else {
    console.log(`${C.red}❌ Failed to post PR comment: ${response.status}${C.reset}`);
    return false;
  }
}

// ─── Main ────────────────────────────────────────────────────

async function main() {
  console.log(`${C.bold}${C.purple}╔══════════════════════════════════════════════════╗${C.reset}`);
  console.log(`${C.bold}${C.purple}║  🤖 AI Code Review Bot (Z AI + GLM-4)           ║${C.reset}`);
  console.log(`${C.bold}${C.purple}╚══════════════════════════════════════════════════╝${C.reset}`);
  
  if (!API_KEY) {
    console.error(`${C.red}❌ ZAI_API_KEY environment variable is required${C.reset}`);
    process.exit(1);
  }
  
  // Get diffs
  const { files, diffs } = opts.files.length > 0
    ? getSpecificFiles(opts.files)
    : getDiff();
  
  console.log(`${C.cyan}📁 Files to review: ${files.length}${C.reset}`);
  if (files.length === 0) {
    console.log(`${C.green}✅ No code changes to review${C.reset}`);
    if (opts.format === 'json') {
      formatJSON({ issues: [], summary: 'No changes to review.' });
    }
    process.exit(0);
  }
  
  files.forEach(f => console.log(`  ${C.dim}• ${f}${C.reset}`));
  console.log('');
  
  // Review with AI
  try {
    const result = await reviewWithAI(diffs);
    
    // Output
    switch (opts.format) {
      case 'json':
        formatJSON(result);
        break;
      case 'markdown':
        const md = formatMarkdown(result);
        console.log(md);
        if (opts.comment) {
          await postPRComment(md);
        }
        break;
      default:
        formatTerminal(result);
        if (opts.comment) {
          const md = formatMarkdown(result);
          await postPRComment(md);
        }
    }
    
    // Exit code: 1 if CRITICAL or HIGH issues found
    const hasCritical = result.issues.some(i => 
      i.severity === 'CRITICAL' || i.severity === 'HIGH'
    );
    process.exit(hasCritical ? 1 : 0);
    
  } catch (e) {
    console.error(`${C.red}❌ Review failed: ${e.message}${C.reset}`);
    process.exit(2);
  }
}

main().catch(e => {
  console.error(`${C.red}Fatal: ${e.message}${C.reset}`);
  process.exit(2);
});
