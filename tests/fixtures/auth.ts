import { test as base } from '@playwright/test';
import { LoginPage } from '../pages/LoginPage';

type AuthFixtures = {
  authenticatedPage: any;
};

export const test = base.extend<AuthFixtures>({
  authenticatedPage: async ({ page }, use) => {
    // Navigate to login page
    const loginPage = new LoginPage(page);
    await loginPage.navigate();
    
    // Check if already logged in by trying to access admin dashboard
    await page.goto('/admin/dash.php');
    
    // If redirected to login, perform login
    if (await loginPage.isOnLoginPage()) {
      // Use default admin credentials - adjust these based on your system
      await loginPage.login('admin', 'admin123');
      
      // Wait for successful login (redirect to dashboard)
      await page.waitForURL('**/admin/dash.php', { timeout: 10000 });
    }
    
    await use(page);
  },
});

export { expect } from '@playwright/test';