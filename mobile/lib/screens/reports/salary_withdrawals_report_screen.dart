import 'package:flutter/material.dart';

import 'expenses_report_screen.dart';

class SalaryWithdrawalsReportScreen extends StatelessWidget {
  const SalaryWithdrawalsReportScreen({super.key});

  static const Set<String> _salaryTypes = {
    'salary',
    'salaries',
    'salary_withdrawal',
    'salary-withdrawal',
    'رواتب',
    'سحب راتب',
  };

  @override
  Widget build(BuildContext context) {
    return ExpensesReportScreen(
      title: 'تقرير سحبيات الرواتب',
      typeLabel: 'نوع السحب',
      allowedTypes: _salaryTypes,
      showTypeFilter: false,
      includeEmployeeDetails: true,
    );
  }
}
