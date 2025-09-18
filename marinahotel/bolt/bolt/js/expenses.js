// Expenses management functions
function loadExpensesSection() {
    const expensesSection = document.getElementById('expensesSection');
    expensesSection.innerHTML = `
        <div class="flex justify-between items-center mb-6">
            <h2 class="text-2xl font-bold text-gray-800">إدارة المصروفات</h2>
            <button onclick="openAddExpenseModal()" class="btn-primary text-white px-6 py-2 rounded-lg">
                <i class="fas fa-plus ml-2"></i>
                إضافة مصروف
            </button>
        </div>
        <div class="bg-white rounded-xl shadow-sm">
            <div class="overflow-x-auto">
                <table class="w-full table-hover">
                    <thead class="bg-gray-50">
                        <tr>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">رقم المصروف</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">نوع المصروف</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">الوصف</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">المبلغ</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">التاريخ</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">الإجراءات</th>
                        </tr>
                    </thead>
                    <tbody id="expensesTable" class="divide-y divide-gray-200">
                        <!-- Data will be populated here -->
                    </tbody>
                </table>
            </div>
        </div>
    `;
    
    loadExpenses();
}

function loadExpenses() {
    const expenses = dataManager.getData('expenses');
    const expensesTable = document.getElementById('expensesTable');
    if (!expensesTable) return;
    
    expensesTable.innerHTML = '';
    
    const expenseTypes = {
        'utilities': 'مرافق',
        'other': 'أخرى',
        'purchases': 'مشتريات',
        'maintenance': 'صيانة',
        'salaries': 'رواتب'
    };
    
    expenses.forEach(expense => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${expense.id}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${expenseTypes[expense.expense_type] || expense.expense_type}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${expense.description}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${formatCurrency(expense.amount)}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${formatDate(expense.date)}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                <button onclick="editExpense(${expense.id})" class="text-blue-600 hover:text-blue-900 ml-2">
                    <i class="fas fa-edit"></i>
                </button>
                <button onclick="deleteExpense(${expense.id})" class="text-red-600 hover:text-red-900">
                    <i class="fas fa-trash"></i>
                </button>
            </td>
        `;
        expensesTable.appendChild(row);
    });
}

function editExpense(expenseId) {
    const expenses = dataManager.getData('expenses');
    const expense = expenses.find(e => e.id === expenseId);
    if (expense) {
        openExpenseModal(expense);
    }
}

function deleteExpense(expenseId) {
    showConfirmation('هل أنت متأكد من حذف هذا المصروف؟', () => {
        if (dataManager.deleteItem('expenses', expenseId)) {
            loadExpenses();
            showNotification('تم حذف المصروف بنجاح');
        }
    });
}