# Flutter analyze remediation

- SDK: Flutter 3.44.6 (Dart 3.12.2)
- Scope: `mobile/`
- Initial run: 8 diagnostics (1 warning, 7 info)
- Final run: 0 diagnostics (`No issues found!`)

## Resolved diagnostics

1. Removed the unused `_cancelled` field and obsolete `cancel()` method from the disabled direct D1 upload service.
2. Replaced two conditional list expressions in `hotel_day_key_fix_service.dart` with collection `if` elements.
3. Corrected quote style in the restore-admission SQL query.
4. Added the missing final newline to `sync/pull_apply_rules.dart`.
5. Replaced three unnecessary null assertions in Cloudflare schema-contract tests with explicit safe null narrowing. An intermediate analyzer run exposed two nullable-key type errors; the final narrowing resolves both without assertions.

The final raw analyzer output is retained in `analyze_report.txt`.

Recommendations 5, 6, 7, and 8 from `mobile_analysis_draft.md` were intentionally not implemented, per the user's instruction.
