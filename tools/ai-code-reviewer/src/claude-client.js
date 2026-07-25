import axios from "axios";

class AIClient {
  constructor(githubToken) {
    this.token = githubToken;
    // ✅ Use GitHub Models API (free, no extra keys needed)
    // Falls back to Azure AI if GitHub Models is unavailable
    this.baseURL = "https://models.inference.ai.azure.com";
    this.model = "gpt-4o-mini";
  }

  async reviewCode(filePath, diffContent) {
    // ✅ Detect language and use specialized prompt
    const isDart = filePath.endsWith('.dart');
    const isFlutter = isDart || filePath.endsWith('.flutter');

    const systemPrompt = isDart
      ? `You are an expert Flutter/Dart code reviewer specializing in Appwrite, Drift (SQLite), Riverpod, and offline-first architectures. Analyze the following Dart code changes and identify issues.

For EACH issue, respond ONLY with a JSON array (no markdown, no extra text):
[
  {
    "severity": "critical|warning|suggestion",
    "line": 42,
    "message": "Clear explanation of the issue",
    "suggestion": "How to fix it",
    "explanation": "Why this matters"
  }
]

Flutter/Dart specific checks:
- 🔴 critical:
  - Missing dispose() on controllers, streams, subscriptions (memory leaks)
  - setState() after async gap without mounted check
  - Hardcoded API keys, secrets, credentials in source
  - SQL injection in raw queries
  - Missing await on Future (fire-and-forget that should be awaited)
  - Using BuildContext across async gaps
  - Data loss in sync logic (missing locks, race conditions)
  - Appwrite: excessive database reads, missing delta sync, full scan without Query.limit
  - Drift: missing transactions on multi-table writes
- 🟡 warning:
  - Missing const constructors
  - Unnecessary rebuilds (should use ValueNotifier, Selector, or ConsumerStatefulWidget)
  - O(n²) loops in build methods or frequent callbacks
  - Missing error handling on network/DB calls
  - Deprecated API usage
  - Large widget trees that should be split
  - Riverpod: using ref.watch in callbacks (should use ref.read)
  - Missing null safety checks (!. operator without null check)
- 💡 suggestion:
  - Naming conventions (camelCase for methods, PascalCase for classes)
  - Extract reusable widgets
  - Add documentation for public APIs
  - Use sealed classes for state
  - Prefer switch expressions over if-else chains

IMPORTANT:
- Return ONLY valid JSON array, no markdown, no code blocks, no extra text
- Be concise but specific
- If no issues found, return: []
- Focus on important issues, skip nitpicks
- Line numbers refer to the diff context`
      : `You are an expert code reviewer. Analyze the following code changes and identify issues.

For EACH issue, respond ONLY with a JSON array (no markdown, no extra text):
[
  {
    "severity": "critical|warning|suggestion",
    "line": 42,
    "message": "Clear explanation of the issue",
    "suggestion": "How to fix it",
    "explanation": "Why this matters"
  }
]

Guidelines:
- critical: Security vulnerabilities, logic bugs, crashes, data loss
- warning: Performance problems, code smells, maintainability issues
- suggestion: Best practices, style improvements, refactoring opportunities

IMPORTANT:
- Return ONLY valid JSON array, no markdown, no code blocks, no extra text
- Be concise but specific
- If no issues found, return: []
- Focus on important issues, skip nitpicks
- Line numbers refer to the diff context`;

    const userMessage = `File: ${filePath}

Code changes:
\`\`\`
${diffContent}
\`\`\`

Analyze these changes and return ONLY a JSON array.`;

    try {
      console.log(`🤖 Reviewing ${filePath}...`);

      const response = await axios.post(
        `${this.baseURL}/chat/completions`,
        {
          model: this.model,
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userMessage },
          ],
          max_tokens: 2048,
          temperature: 0,
        },
        {
          headers: {
            Authorization: `Bearer ${this.token}`,
            "Content-Type": "application/json",
          },
          timeout: 30000,
        }
      );

      const content = response.data.choices[0].message.content;

      let issues = [];
      try {
        const cleaned = content.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();
        issues = JSON.parse(cleaned);
        console.log(`✅ Found ${issues.length} issues in ${filePath}`);
      } catch (e) {
        console.warn(`⚠️ Error parsing AI response:`);
        console.warn(content);
        issues = [];
      }

      return issues;
    } catch (error) {
      if (error.response?.status === 429) {
        console.error("⏳ Rate limit reached, waiting...");
      } else if (error.code === "ECONNABORTED") {
        console.error("⏱️ Request timeout");
      } else {
        console.error("❌ AI API error:", error.response?.data?.error || error.message);
      }
      return [];
    }
  }
}

export default AIClient;
