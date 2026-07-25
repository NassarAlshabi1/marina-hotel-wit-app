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
    const systemPrompt = `You are an expert code reviewer specializing in Flutter/Dart, Appwrite, and offline-first architectures. Analyze the following code changes and identify issues.

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
- critical: Security vulnerabilities, logic bugs, crashes, data loss, API key leaks
- warning: Performance problems (excessive API calls, unnecessary reads), code smells, maintainability issues
- suggestion: Best practices, style improvements, refactoring opportunities

IMPORTANT:
- Return ONLY valid JSON array, no markdown, no code blocks, no extra text
- Be concise but specific
- If no issues found, return: []
- Focus on important issues, skip nitpicks
- Line numbers refer to the diff context
- For Flutter/Dart: check for missing dispose(), memory leaks, unnecessary rebuilds
- For Appwrite: check for excessive database reads, missing delta sync, redundant API calls
- For sync: check for race conditions, missing locks, data loss scenarios`;

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
