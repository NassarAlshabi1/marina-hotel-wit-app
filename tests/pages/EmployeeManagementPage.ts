import { Page, Locator, expect } from '@playwright/test';
import { BasePage } from './BasePage';

export class EmployeeManagementPage extends BasePage {
    // Page elements
    readonly pageTitle: Locator;
    readonly addEmployeeForm: Locator;
    readonly nameInput: Locator;
    readonly salaryInput: Locator;
    readonly statusSelect: Locator;
    readonly addEmployeeButton: Locator;
    readonly employeesTable: Locator;
    readonly noEmployeesMessage: Locator;
    readonly deleteEmployeeModal: Locator;
    readonly editEmployeeModal: Locator;
    readonly successAlert: Locator;
    readonly errorAlert: Locator;

    // Modal elements
    readonly deleteEmployeeName: Locator;
    readonly deleteEmployeeId: Locator;
    readonly deleteConfirmButton: Locator;
    readonly deleteCancelButton: Locator;
    
    readonly editEmployeeId: Locator;
    readonly editNameInput: Locator;
    readonly editSalaryInput: Locator;
    readonly editStatusSelect: Locator;
    readonly editSaveButton: Locator;
    readonly editCancelButton: Locator;

    constructor(page: Page) {
        super(page);
        
        // Initialize page elements
        this.pageTitle = page.locator('h2:has-text("إدارة الموظفين")');
        this.addEmployeeForm = page.locator('#addEmployeeForm');
        this.nameInput = page.locator('#name');
        this.salaryInput = page.locator('#basic_salary');
        this.statusSelect = page.locator('#status');
        this.addEmployeeButton = page.locator('button[name="add_employee"]');
        this.employeesTable = page.locator('#employeesTable');
        this.noEmployeesMessage = page.locator('#noEmployeesMessage');
        this.deleteEmployeeModal = page.locator('#deleteEmployeeModal');
        this.editEmployeeModal = page.locator('#editEmployeeModal');
        this.successAlert = page.locator('.alert-success');
        this.errorAlert = page.locator('.alert-danger');

        // Modal elements
        this.deleteEmployeeName = page.locator('#deleteEmployeeName');
        this.deleteEmployeeId = page.locator('#deleteEmployeeId');
        this.deleteConfirmButton = page.locator('button[name="delete_employee"]');
        this.deleteCancelButton = page.locator('#deleteEmployeeModal .btn-secondary');
        
        this.editEmployeeId = page.locator('#editEmployeeId');
        this.editNameInput = page.locator('#edit_name');
        this.editSalaryInput = page.locator('#edit_basic_salary');
        this.editStatusSelect = page.locator('#edit_status');
        this.editSaveButton = page.locator('button[name="edit_employee"]');
        this.editCancelButton = page.locator('#editEmployeeModal .btn-secondary');
    }

    async navigate(): Promise<void> {
        await this.page.goto('/admin/settings/add_employee.php');
        await this.waitForPageLoad();
    }

    async waitForPageLoad(): Promise<void> {
        await expect(this.pageTitle).toBeVisible();
        await expect(this.addEmployeeForm).toBeVisible();
    }

    async addEmployee(name: string, salary: number = 0, status: string = 'active'): Promise<void> {
        await this.nameInput.fill(name);
        await this.salaryInput.fill(salary.toString());
        await this.statusSelect.selectOption(status);
        await this.addEmployeeButton.click();
        await this.waitForPageLoad();
    }

    async editEmployee(employeeId: string, name: string, salary: number = 0, status: string = 'active'): Promise<void> {
        // Find and click edit button for the specific employee
        const editButton = this.page.locator(`button.edit-employee[data-id="${employeeId}"]`);
        await editButton.click();
        
        // Wait for modal to be visible
        await expect(this.editEmployeeModal).toBeVisible();
        
        // Fill the edit form
        await this.editNameInput.fill(name);
        await this.editSalaryInput.fill(salary.toString());
        await this.editStatusSelect.selectOption(status);
        
        // Save the changes
        await this.editSaveButton.click();
        await this.waitForPageLoad();
    }

    async deleteEmployee(employeeId: string): Promise<void> {
        // Find and click delete button for the specific employee
        const deleteButton = this.page.locator(`button.delete-employee[data-id="${employeeId}"]`);
        await deleteButton.click();
        
        // Wait for modal to be visible
        await expect(this.deleteEmployeeModal).toBeVisible();
        
        // Confirm deletion
        await this.deleteConfirmButton.click();
        await this.waitForPageLoad();
    }

    async getEmployeeData(employeeId: string): Promise<{
        id: string;
        name: string;
        salary: string;
        status: string;
        createdAt: string;
    } | null> {
        const row = this.page.locator(`tr[data-employee-id="${employeeId}"]`);
        
        if (await row.count() === 0) {
            return null;
        }

        const cells = row.locator('td');
        
        return {
            id: await cells.nth(0).textContent() || '',
            name: await cells.nth(1).textContent() || '',
            salary: await cells.nth(2).textContent() || '',
            status: await cells.nth(3).textContent() || '',
            createdAt: await cells.nth(4).textContent() || ''
        };
    }

    async getEmployeeCount(): Promise<number> {
        // If no employees message is visible, return 0
        if (await this.noEmployeesMessage.isVisible()) {
            return 0;
        }
        
        // Count table rows (excluding header)
        const rows = this.employeesTable.locator('tbody tr');
        return await rows.count();
    }

    async getEmployeesList(): Promise<Array<{
        id: string;
        name: string;
        salary: string;
        status: string;
        createdAt: string;
    }>> {
        const employees = [];
        const rows = this.employeesTable.locator('tbody tr');
        const count = await rows.count();
        
        for (let i = 0; i < count; i++) {
            const cells = rows.nth(i).locator('td');
            employees.push({
                id: await cells.nth(0).textContent() || '',
                name: await cells.nth(1).textContent() || '',
                salary: await cells.nth(2).textContent() || '',
                status: await cells.nth(3).textContent() || '',
                createdAt: await cells.nth(4).textContent() || ''
            });
        }
        
        return employees;
    }

    async isEmployeeExists(employeeId: string): Promise<boolean> {
        const row = this.page.locator(`tr[data-employee-id="${employeeId}"]`);
        return await row.count() > 0;
    }

    async getLastAddedEmployeeId(): Promise<string | null> {
        const rows = this.employeesTable.locator('tbody tr');
        const count = await rows.count();
        
        if (count === 0) {
            return null;
        }
        
        // Get the first row (since they are ordered by ID DESC)
        const firstRow = rows.nth(0);
        const idCell = firstRow.locator('td').nth(0);
        return await idCell.textContent();
    }

    async validateSuccessMessage(expectedMessage: string): Promise<void> {
        await expect(this.successAlert).toBeVisible();
        await expect(this.successAlert).toContainText(expectedMessage);
    }

    async validateErrorMessage(expectedMessage: string): Promise<void> {
        await expect(this.errorAlert).toBeVisible();
        await expect(this.errorAlert).toContainText(expectedMessage);
    }

    async validateFormValidation(): Promise<void> {
        // Try to submit form with empty name
        await this.addEmployeeButton.click();
        
        // Check if name input has validation error
        await expect(this.nameInput).toHaveClass(/is-invalid/);
    }

    async validateEmployeeInTable(name: string, salary: string, status: string): Promise<void> {
        const nameCell = this.employeesTable.locator(`td:has-text("${name}")`);
        await expect(nameCell).toBeVisible();
        
        const salaryCell = this.employeesTable.locator(`td:has-text("${salary}")`);
        await expect(salaryCell).toBeVisible();
        
        const statusBadge = this.employeesTable.locator(`.badge:has-text("${status}")`);
        await expect(statusBadge).toBeVisible();
    }

    async clearForm(): Promise<void> {
        await this.nameInput.fill('');
        await this.salaryInput.fill('0');
        await this.statusSelect.selectOption('active');
    }

    async navigateToSettings(): Promise<void> {
        const settingsLink = this.page.locator('a[href="index.php"]:has-text("العودة للإعدادات")');
        await settingsLink.click();
    }

    async navigateToDashboard(): Promise<void> {
        const dashboardLink = this.page.locator('a[href="../dash.php"]:has-text("لوحة التحكم")');
        await dashboardLink.click();
    }
}