import { test, expect } from '../fixtures/auth';
import { EmployeeManagementPage } from '../pages/EmployeeManagementPage';

test.describe('إدارة الموظفين - Employee Management', () => {
    let employeeManagementPage: EmployeeManagementPage;
    let testEmployeeId: string | null = null;

    test.beforeEach(async ({ authenticatedPage }) => {
        employeeManagementPage = new EmployeeManagementPage(authenticatedPage);
        await employeeManagementPage.navigate();
    });

    test.afterEach(async () => {
        // Clean up: delete test employee if it exists
        if (testEmployeeId && await employeeManagementPage.isEmployeeExists(testEmployeeId)) {
            await employeeManagementPage.deleteEmployee(testEmployeeId);
        }
    });

    test('يجب أن تعرض صفحة إدارة الموظفين بشكل صحيح', async () => {
        // التحقق من عنوان الصفحة
        await expect(employeeManagementPage.pageTitle).toBeVisible();
        await expect(employeeManagementPage.pageTitle).toContainText('إدارة الموظفين');
        
        // التحقق من وجود نموذج إضافة موظف
        await expect(employeeManagementPage.addEmployeeForm).toBeVisible();
        await expect(employeeManagementPage.nameInput).toBeVisible();
        await expect(employeeManagementPage.salaryInput).toBeVisible();
        await expect(employeeManagementPage.statusSelect).toBeVisible();
        await expect(employeeManagementPage.addEmployeeButton).toBeVisible();
        
        // التحقق من الأزرار التنقل
        const settingsLink = employeeManagementPage.page.locator('a:has-text("العودة للإعدادات")');
        const dashboardLink = employeeManagementPage.page.locator('a:has-text("لوحة التحكم")');
        
        await expect(settingsLink).toBeVisible();
        await expect(dashboardLink).toBeVisible();
    });

    test('يجب أن يتم إضافة موظف جديد بنجاح', async () => {
        const employeeName = 'أحمد محمد علي';
        const employeeSalary = 50000;
        const employeeStatus = 'active';
        
        // إضافة موظف جديد
        await employeeManagementPage.addEmployee(employeeName, employeeSalary, employeeStatus);
        
        // التحقق من رسالة النجاح
        await employeeManagementPage.validateSuccessMessage('تم إضافة الموظف بنجاح');
        
        // التحقق من وجود الموظف في الجدول
        await employeeManagementPage.validateEmployeeInTable(employeeName, '50,000.00 ريال', 'نشط');
        
        // الحصول على معرف الموظف المضاف للتنظيف لاحقاً
        testEmployeeId = await employeeManagementPage.getLastAddedEmployeeId();
        expect(testEmployeeId).toBeTruthy();
    });

    test('يجب أن يتم إضافة موظف بدون راتب', async () => {
        const employeeName = 'فاطمة أحمد';
        const employeeSalary = 0;
        const employeeStatus = 'active';
        
        // إضافة موظف بدون راتب
        await employeeManagementPage.addEmployee(employeeName, employeeSalary, employeeStatus);
        
        // التحقق من رسالة النجاح
        await employeeManagementPage.validateSuccessMessage('تم إضافة الموظف بنجاح');
        
        // التحقق من وجود الموظف في الجدول
        await employeeManagementPage.validateEmployeeInTable(employeeName, '0.00 ريال', 'نشط');
        
        // الحصول على معرف الموظف المضاف للتنظيف لاحقاً
        testEmployeeId = await employeeManagementPage.getLastAddedEmployeeId();
    });

    test('يجب أن يتم إضافة موظف غير نشط', async () => {
        const employeeName = 'محمد خالد';
        const employeeSalary = 30000;
        const employeeStatus = 'inactive';
        
        // إضافة موظف غير نشط
        await employeeManagementPage.addEmployee(employeeName, employeeSalary, employeeStatus);
        
        // التحقق من رسالة النجاح
        await employeeManagementPage.validateSuccessMessage('تم إضافة الموظف بنجاح');
        
        // التحقق من وجود الموظف في الجدول
        await employeeManagementPage.validateEmployeeInTable(employeeName, '30,000.00 ريال', 'غير نشط');
        
        // الحصول على معرف الموظف المضاف للتنظيف لاحقاً
        testEmployeeId = await employeeManagementPage.getLastAddedEmployeeId();
    });

    test('يجب أن يظهر خطأ عند إضافة موظف بدون اسم', async () => {
        // محاولة إضافة موظف بدون اسم
        await employeeManagementPage.addEmployee('', 25000, 'active');
        
        // التحقق من رسالة الخطأ
        await employeeManagementPage.validateErrorMessage('يرجى إدخال اسم الموظف');
        
        // التحقق من أن النموذج يظهر validation error
        await employeeManagementPage.validateFormValidation();
    });

    test('يجب أن يتم تعديل موظف موجود بنجاح', async () => {
        // إضافة موظف أولاً
        const originalName = 'عبدالله سعيد';
        const originalSalary = 40000;
        
        await employeeManagementPage.addEmployee(originalName, originalSalary, 'active');
        testEmployeeId = await employeeManagementPage.getLastAddedEmployeeId();
        
        // تعديل الموظف
        const newName = 'عبدالله سعيد المحدث';
        const newSalary = 45000;
        const newStatus = 'inactive';
        
        if (testEmployeeId) {
            await employeeManagementPage.editEmployee(testEmployeeId, newName, newSalary, newStatus);
            
            // التحقق من رسالة النجاح
            await employeeManagementPage.validateSuccessMessage('تم تعديل الموظف بنجاح');
            
            // التحقق من تحديث البيانات في الجدول
            await employeeManagementPage.validateEmployeeInTable(newName, '45,000.00 ريال', 'غير نشط');
        }
    });

    test('يجب أن يتم حذف موظف موجود بنجاح', async () => {
        // إضافة موظف أولاً
        const employeeName = 'خالد أحمد';
        const employeeSalary = 35000;
        
        await employeeManagementPage.addEmployee(employeeName, employeeSalary, 'active');
        testEmployeeId = await employeeManagementPage.getLastAddedEmployeeId();
        
        // التحقق من وجود الموظف
        if (testEmployeeId) {
            expect(await employeeManagementPage.isEmployeeExists(testEmployeeId)).toBe(true);
            
            // حذف الموظف
            await employeeManagementPage.deleteEmployee(testEmployeeId);
            
            // التحقق من رسالة النجاح
            await employeeManagementPage.validateSuccessMessage('تم حذف الموظف بنجاح');
            
            // التحقق من عدم وجود الموظف في الجدول
            expect(await employeeManagementPage.isEmployeeExists(testEmployeeId)).toBe(false);
            
            // إعادة تعيين لتجنب التنظيف في afterEach
            testEmployeeId = null;
        }
    });

    test('يجب أن يعرض قائمة الموظفين بشكل صحيح', async () => {
        // إضافة عدة موظفين
        const employees = [
            { name: 'الموظف الأول', salary: 30000, status: 'active' },
            { name: 'الموظف الثاني', salary: 40000, status: 'inactive' },
            { name: 'الموظف الثالث', salary: 35000, status: 'active' }
        ];
        
        const addedEmployeeIds: string[] = [];
        
        for (const employee of employees) {
            await employeeManagementPage.addEmployee(employee.name, employee.salary, employee.status);
            const employeeId = await employeeManagementPage.getLastAddedEmployeeId();
            if (employeeId) {
                addedEmployeeIds.push(employeeId);
            }
        }
        
        // التحقق من عدد الموظفين
        const employeeCount = await employeeManagementPage.getEmployeeCount();
        expect(employeeCount).toBeGreaterThanOrEqual(3);
        
        // التحقق من بيانات الموظفين
        const employeesList = await employeeManagementPage.getEmployeesList();
        expect(employeesList.length).toBeGreaterThanOrEqual(3);
        
        // التحقق من وجود الموظفين المضافين
        for (let i = 0; i < employees.length; i++) {
            const statusText = employees[i].status === 'active' ? 'نشط' : 'غير نشط';
            await employeeManagementPage.validateEmployeeInTable(
                employees[i].name, 
                `${employees[i].salary.toLocaleString()}.00 ريال`, 
                statusText
            );
        }
        
        // تنظيف الموظفين المضافين
        for (const employeeId of addedEmployeeIds) {
            if (await employeeManagementPage.isEmployeeExists(employeeId)) {
                await employeeManagementPage.deleteEmployee(employeeId);
            }
        }
    });

    test('يجب أن يعمل التنقل بين الصفحات بشكل صحيح', async () => {
        // اختبار التنقل إلى صفحة الإعدادات
        await employeeManagementPage.navigateToSettings();
        expect(employeeManagementPage.page.url()).toContain('settings/index.php');
        
        // العودة إلى صفحة الموظفين
        await employeeManagementPage.navigate();
        
        // اختبار التنقل إلى لوحة التحكم
        await employeeManagementPage.navigateToDashboard();
        expect(employeeManagementPage.page.url()).toContain('dash.php');
    });

    test('يجب أن تعمل مودالات التأكيد بشكل صحيح', async () => {
        // إضافة موظف للاختبار
        const employeeName = 'موظف للاختبار';
        await employeeManagementPage.addEmployee(employeeName, 25000, 'active');
        testEmployeeId = await employeeManagementPage.getLastAddedEmployeeId();
        
        if (testEmployeeId) {
            // اختبار مودال التعديل
            const editButton = employeeManagementPage.page.locator(`button.edit-employee[data-id="${testEmployeeId}"]`);
            await editButton.click();
            
            // التحقق من ظهور مودال التعديل
            await expect(employeeManagementPage.editEmployeeModal).toBeVisible();
            
            // إغلاق المودال
            await employeeManagementPage.editCancelButton.click();
            await expect(employeeManagementPage.editEmployeeModal).not.toBeVisible();
            
            // اختبار مودال الحذف
            const deleteButton = employeeManagementPage.page.locator(`button.delete-employee[data-id="${testEmployeeId}"]`);
            await deleteButton.click();
            
            // التحقق من ظهور مودال الحذف
            await expect(employeeManagementPage.deleteEmployeeModal).toBeVisible();
            
            // التحقق من عرض اسم الموظف في مودال الحذف
            await expect(employeeManagementPage.deleteEmployeeName).toContainText(employeeName);
            
            // إغلاق المودال
            await employeeManagementPage.deleteCancelButton.click();
            await expect(employeeManagementPage.deleteEmployeeModal).not.toBeVisible();
        }
    });

    test('يجب أن تكون الصفحة متجاوبة مع الأجهزة المحمولة', async ({ authenticatedPage }) => {
        // تغيير حجم الشاشة للجهاز المحمول
        await authenticatedPage.setViewportSize({ width: 375, height: 667 });
        
        await employeeManagementPage.navigate();
        
        // التحقق من أن العناصر الأساسية ما زالت مرئية
        await expect(employeeManagementPage.pageTitle).toBeVisible();
        await expect(employeeManagementPage.addEmployeeForm).toBeVisible();
        await expect(employeeManagementPage.nameInput).toBeVisible();
        await expect(employeeManagementPage.addEmployeeButton).toBeVisible();
        
        // إضافة موظف للاختبار
        const employeeName = 'موظف الهاتف المحمول';
        await employeeManagementPage.addEmployee(employeeName, 20000, 'active');
        
        // التحقق من عرض البيانات في الجدول
        await employeeManagementPage.validateEmployeeInTable(employeeName, '20,000.00 ريال', 'نشط');
        
        // تنظيف
        testEmployeeId = await employeeManagementPage.getLastAddedEmployeeId();
    });

    test('يجب أن تعمل validation للبيانات المدخلة', async () => {
        // اختبار validation للاسم الفارغ
        await employeeManagementPage.nameInput.fill('');
        await employeeManagementPage.addEmployeeButton.click();
        
        // التحقق من ظهور رسالة validation
        await expect(employeeManagementPage.nameInput).toHaveClass(/is-invalid/);
        
        // اختبار validation للراتب السالب
        await employeeManagementPage.nameInput.fill('موظف اختبار');
        await employeeManagementPage.salaryInput.fill('-1000');
        await employeeManagementPage.addEmployeeButton.click();
        
        // التحقق من ظهور رسالة validation للراتب
        await expect(employeeManagementPage.salaryInput).toHaveClass(/is-invalid/);
        
        // اختبار البيانات الصحيحة
        await employeeManagementPage.nameInput.fill('موظف صحيح');
        await employeeManagementPage.salaryInput.fill('30000');
        await employeeManagementPage.addEmployeeButton.click();
        
        // التحقق من النجاح
        await employeeManagementPage.validateSuccessMessage('تم إضافة الموظف بنجاح');
        
        // تنظيف
        testEmployeeId = await employeeManagementPage.getLastAddedEmployeeId();
    });
});