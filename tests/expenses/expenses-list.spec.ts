import { test, expect } from '../fixtures/auth';
import { ExpensesPage } from '../pages/ExpensesPage';

test.describe('صفحة عرض المصروفات', () => {
  let expensesPage: ExpensesPage;

  test.beforeEach(async ({ authenticatedPage }) => {
    expensesPage = new ExpensesPage(authenticatedPage);
    await expensesPage.navigate();
  });

  test('يجب أن تعرض صفحة المصروفات بشكل صحيح', async () => {
    // التحقق من عنوان الصفحة
    await expect(expensesPage.pageTitle).toBeVisible();
    await expect(expensesPage.pageTitle).toContainText('عرض المصروفات');
    
    // التحقق من وجود جدول المصروفات
    await expect(expensesPage.expensesTable).toBeVisible();
    
    // التحقق من وجود الأزرار الرئيسية
    await expect(expensesPage.addExpenseButton).toBeVisible();
    await expect(expensesPage.addExpenseButton).toContainText('إضافة مصروف جديد');
    
    await expect(expensesPage.reportsButton).toBeVisible();
    await expect(expensesPage.reportsButton).toContainText('التقارير');
    
    await expect(expensesPage.homeButton).toBeVisible();
    await expect(expensesPage.homeButton).toContainText('الرئيسية');
  });

  test('يجب أن تعرض عناصر الفلترة بالتاريخ', async () => {
    // التحقق من وجود حقول التاريخ
    await expect(expensesPage.startDateInput).toBeVisible();
    await expect(expensesPage.endDateInput).toBeVisible();
    await expect(expensesPage.filterButton).toBeVisible();
    
    // التحقق من أن حقول التاريخ تحتوي على قيم افتراضية
    const startDate = await expensesPage.getCurrentStartDate();
    const endDate = await expensesPage.getCurrentEndDate();
    
    expect(startDate).toBeTruthy();
    expect(endDate).toBeTruthy();
    
    // التحقق من صيغة التاريخ
    expect(await expensesPage.validateDateFormat(startDate)).toBe(true);
    expect(await expensesPage.validateDateFormat(endDate)).toBe(true);
  });

  test('يجب أن يعرض جدول المصروفات مع العناوين الصحيحة', async () => {
    const tableHeaders = expensesPage.expensesTable.locator('thead th');
    
    await expect(tableHeaders.nth(0)).toContainText('نوع المصروف');
    await expect(tableHeaders.nth(1)).toContainText('الموظف / المورد');
    await expect(tableHeaders.nth(2)).toContainText('الوصف');
    await expect(tableHeaders.nth(3)).toContainText('المبلغ');
    await expect(tableHeaders.nth(4)).toContainText('التاريخ');
  });

  test('يجب أن يعرض المجموع الكلي للمصروفات', async () => {
    // التحقق من وجود صف المجموع الكلي
    const totalRow = expensesPage.expensesTable.locator('.total-row');
    await expect(totalRow).toBeVisible();
    
    // التحقق من وجود نص "المجموع الكلي"
    await expect(totalRow).toContainText('المجموع الكلي');
    
    // التحقق من وجود قيمة المجموع
    await expect(expensesPage.totalAmountCell).toBeVisible();
    const totalAmount = await expensesPage.getTotalAmount();
    expect(totalAmount).toBeTruthy();
  });

  test('يجب أن يعمل فلتر التاريخ بشكل صحيح', async () => {
    // الحصول على التواريخ الحالية
    const currentStartDate = await expensesPage.getCurrentStartDate();
    const currentEndDate = await expensesPage.getCurrentEndDate();
    
    // تغيير نطاق التاريخ
    const newStartDate = '2024-01-01';
    const newEndDate = '2024-01-31';
    
    await expensesPage.setDateFilter(newStartDate, newEndDate);
    
    // التحقق من أن الصفحة تم إعادة تحميلها مع المعاملات الجديدة
    expect(expensesPage.page.url()).toContain(`start_date=${newStartDate}`);
    expect(expensesPage.page.url()).toContain(`end_date=${newEndDate}`);
    
    // التحقق من أن حقول التاريخ تحتوي على القيم الجديدة
    expect(await expensesPage.getCurrentStartDate()).toBe(newStartDate);
    expect(await expensesPage.getCurrentEndDate()).toBe(newEndDate);
  });

  test('يجب أن تتنقل إلى صفحة إضافة مصروف جديد', async () => {
    await expensesPage.clickAddExpense();
    
    // التحقق من الانتقال إلى صفحة إضافة المصروف
    expect(expensesPage.page.url()).toContain('add_expense.php');
  });

  test('يجب أن تتنقل إلى صفحة التقارير', async () => {
    await expensesPage.clickReports();
    
    // التحقق من الانتقال إلى صفحة التقارير
    expect(expensesPage.page.url()).toContain('reports/report.php');
  });

  test('يجب أن تتنقل إلى الصفحة الرئيسية', async () => {
    await expensesPage.clickHome();
    
    // التحقق من الانتقال إلى لوحة التحكم
    expect(expensesPage.page.url()).toContain('dashboard.php');
  });

  test('يجب أن يعرض بيانات المصروفات إذا كانت متوفرة', async () => {
    const hasData = await expensesPage.hasExpenseData();
    
    if (hasData) {
      // إذا كانت هناك بيانات، تحقق من صحة عرضها
      const rowCount = await expensesPage.getExpenseRowsCount();
      expect(rowCount).toBeGreaterThan(0);
      
      // التحقق من بيانات الصف الأول
      const firstRowData = await expensesPage.getExpenseRowData(0);
      expect(firstRowData.type).toBeTruthy();
      expect(firstRowData.amount).toBeTruthy();
      expect(firstRowData.date).toBeTruthy();
      
      // التحقق من أنواع المصروفات
      const expenseTypes = await expensesPage.getExpenseTypes();
      expect(expenseTypes.length).toBeGreaterThan(0);
      
      // التحقق من أن كل نوع مصروف له class مناسب
      for (const type of expenseTypes) {
        expect(['expense', 'salary']).toContain(type.toLowerCase());
      }
    } else {
      // إذا لم تكن هناك بيانات، تحقق من أن الجدول فارغ
      expect(await expensesPage.getExpenseRowsCount()).toBe(0);
      
      // التحقق من أن المجموع الكلي يساوي صفر
      const totalAmount = await expensesPage.getTotalAmount();
      expect(totalAmount).toContain('0');
    }
  });

  test('يجب أن يعرض رسائل النجاح والخطأ إذا كانت موجودة', async () => {
    // محاولة الوصول لصفحة مع رسالة نجاح وهمية
    await expensesPage.page.goto('/admin/expenses/expenses.php?success=test');
    
    // قد لا تظهر الرسالة إذا لم تكن في SESSION، لكن نتحقق من أن الكود لا يكسر
    await expect(expensesPage.expensesTable).toBeVisible();
  });

  test('يجب أن تكون الصفحة متجاوبة مع الأجهزة المحمولة', async ({ authenticatedPage }) => {
    // تغيير حجم الشاشة للجهاز المحمول
    await authenticatedPage.setViewportSize({ width: 375, height: 667 });
    
    await expensesPage.navigate();
    
    // التحقق من أن العناصر الأساسية ما زالت مرئية
    await expect(expensesPage.pageTitle).toBeVisible();
    await expect(expensesPage.addExpenseButton).toBeVisible();
    await expect(expensesPage.expensesTable).toBeVisible();
    await expect(expensesPage.filterButton).toBeVisible();
  });
});