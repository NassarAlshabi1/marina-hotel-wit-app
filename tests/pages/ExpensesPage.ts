import { Page, Locator } from '@playwright/test';
import { BasePage } from './BasePage';

export class ExpensesPage extends BasePage {
  // Page elements
  readonly pageTitle: Locator;
  readonly addExpenseButton: Locator;
  readonly reportsButton: Locator;
  readonly homeButton: Locator;
  readonly startDateInput: Locator;
  readonly endDateInput: Locator;
  readonly filterButton: Locator;
  readonly expensesTable: Locator;
  readonly expenseRows: Locator;
  readonly totalAmountCell: Locator;

  constructor(page: Page) {
    super(page);
    this.pageTitle = page.locator('h1.page-title');
    this.addExpenseButton = page.locator('a[href="add_expense.php"]');
    this.reportsButton = page.locator('a[href="../reports/report.php"]');
    this.homeButton = page.locator('a[href="../dashboard.php"]');
    this.startDateInput = page.locator('#start-date');
    this.endDateInput = page.locator('#end-date');
    this.filterButton = page.locator('#filter-button');
    this.expensesTable = page.locator('.table-custom');
    this.expenseRows = page.locator('.table-custom tbody tr:not(.total-row)');
    this.totalAmountCell = page.locator('.total-row .amount-cell');
  }

  async navigate(): Promise<void> {
    await this.page.goto('/admin/expenses/expenses.php');
    await this.waitForPageLoad();
  }

  async getPageTitle(): Promise<string> {
    return await this.pageTitle.textContent() || '';
  }

  async isExpensesTableVisible(): Promise<boolean> {
    return await this.expensesTable.isVisible();
  }

  async getExpenseRowsCount(): Promise<number> {
    return await this.expenseRows.count();
  }

  async getTotalAmount(): Promise<string> {
    return await this.totalAmountCell.textContent() || '';
  }

  async setDateFilter(startDate: string, endDate: string): Promise<void> {
    await this.startDateInput.fill(startDate);
    await this.endDateInput.fill(endDate);
    await this.filterButton.click();
    await this.waitForPageLoad();
  }

  async getCurrentStartDate(): Promise<string> {
    return await this.startDateInput.inputValue();
  }

  async getCurrentEndDate(): Promise<string> {
    return await this.endDateInput.inputValue();
  }

  async clickAddExpense(): Promise<void> {
    await this.addExpenseButton.click();
    await this.waitForPageLoad();
  }

  async clickReports(): Promise<void> {
    await this.reportsButton.click();
    await this.waitForPageLoad();
  }

  async clickHome(): Promise<void> {
    await this.homeButton.click();
    await this.waitForPageLoad();
  }

  async getExpenseRowData(rowIndex: number): Promise<{
    type: string;
    relatedEntity: string;
    description: string;
    amount: string;
    date: string;
  }> {
    const row = this.expenseRows.nth(rowIndex);
    const cells = row.locator('td');
    
    return {
      type: await cells.nth(0).textContent() || '',
      relatedEntity: await cells.nth(1).textContent() || '',
      description: await cells.nth(2).textContent() || '',
      amount: await cells.nth(3).textContent() || '',
      date: await cells.nth(4).textContent() || ''
    };
  }

  async verifyExpenseRowContains(rowIndex: number, expectedData: Partial<{
    type: string;
    description: string;
    amount: string;
  }>): Promise<boolean> {
    const rowData = await this.getExpenseRowData(rowIndex);
    
    if (expectedData.type && !rowData.type.includes(expectedData.type)) return false;
    if (expectedData.description && !rowData.description.includes(expectedData.description)) return false;
    if (expectedData.amount && !rowData.amount.includes(expectedData.amount)) return false;
    
    return true;
  }

  async getExpenseTypes(): Promise<string[]> {
    const typeElements = this.expenseRows.locator('td:first-child .badge-custom');
    const count = await typeElements.count();
    const types: string[] = [];
    
    for (let i = 0; i < count; i++) {
      const type = await typeElements.nth(i).textContent();
      if (type) types.push(type.trim());
    }
    
    return types;
  }

  // Helper method to validate date format
  async validateDateFormat(dateString: string): Promise<boolean> {
    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    return dateRegex.test(dateString);
  }

  // Helper method to check if table has data
  async hasExpenseData(): Promise<boolean> {
    const rowCount = await this.getExpenseRowsCount();
    return rowCount > 0;
  }
}