import 'package:flutter/material.dart';

import 'expenses_report_screen.dart';

class SalaryWithdrawalsReportScreen extends StatelessWidget {
  const SalaryWithdrawalsReportScreen({super.key});

  static const Set<String> _salaryTypes = {
    'salary',
    'salaries',
    'salary_withdrawal',
    'salary-withdrawal',
    'salary_deduction',
    'salary-deduction',
    'رواتب',
    'سحب راتب',
    'سحب من الراتب',
    'خصم راتب',
    'خصم من الراتب',
  };

  @override
  Widget build(BuildContext context) {
    return const ExpensesReportScreen(
      title: 'تقرير سحبيات الرواتب',
      typeLabel: 'نوع السحب',
      allowedTypes: _salaryTypes,
      showTypeFilter: false,
      includeEmployeeDetails: true,
      totalSummaryLabel: 'إجمالي سحبيات الرواتب',
      totalRowLabel: 'إجمالي سحبيات الرواتب',
    );
  }
}
