import { Page, Locator } from '@playwright/test';

export class BasePage {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  // Common elements
  get successAlert(): Locator {
    return this.page.locator('.alert-success');
  }

  get errorAlert(): Locator {
    return this.page.locator('.alert-danger');
  }

  // Common actions
  async waitForPageLoad(): Promise<void> {
    await this.page.waitForLoadState('networkidle');
  }

  async takeScreenshot(name: string): Promise<void> {
    await this.page.screenshot({ path: `screenshots/${name}.png`, fullPage: true });
  }
}