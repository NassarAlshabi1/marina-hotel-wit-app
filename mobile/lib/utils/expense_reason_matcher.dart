/// Utility for matching expense references in salary withdrawal reason text.
///
/// Uses a regex with a negative lookahead to prevent `exp_1` from matching
/// `exp_10`, `exp_100`, etc.
bool matchesExpenseRef(String? reason, int expenseId) {
  if (reason == null) return false;
  return RegExp('exp_' + expenseId.toString() + r'(?!\d)').hasMatch(reason);
}
