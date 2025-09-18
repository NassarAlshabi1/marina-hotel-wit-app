// Employees management functions
function loadEmployeesSection() {
    const employeesSection = document.getElementById('employeesSection');
    employeesSection.innerHTML = `
        <div class="flex justify-between items-center mb-6">
            <h2 class="text-2xl font-bold text-gray-800">إدارة الموظفين</h2>
            <button onclick="openAddEmployeeModal()" class="btn-primary text-white px-6 py-2 rounded-lg">
                <i class="fas fa-plus ml-2"></i>
                إضافة موظف
            </button>
        </div>
        <div class="bg-white rounded-xl shadow-sm">
            <div class="overflow-x-auto">
                <table class="w-full table-hover">
                    <thead class="bg-gray-50">
                        <tr>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">رقم الموظف</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">الاسم</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">الراتب الأساسي</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">الحالة</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">الإجراءات</th>
                        </tr>
                    </thead>
                    <tbody id="employeesTable" class="divide-y divide-gray-200">
                        <!-- Data will be populated here -->
                    </tbody>
                </table>
            </div>
        </div>
    `;
    
    loadEmployees();
}

function loadEmployees() {
    const employees = dataManager.getData('employees');
    const employeesTable = document.getElementById('employeesTable');
    if (!employeesTable) return;
    
    employeesTable.innerHTML = '';
    
    employees.forEach(employee => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${employee.id}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${employee.name}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${formatCurrency(employee.basic_salary)}</td>
            <td class="px-6 py-4 whitespace-nowrap">
                <span class="px-2 py-1 text-xs rounded-full ${employee.status === 'active' ? 'status-available' : 'status-occupied'}">
                    ${employee.status === 'active' ? 'نشط' : 'غير نشط'}
                </span>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                <button onclick="editEmployee(${employee.id})" class="text-blue-600 hover:text-blue-900 ml-2">
                    <i class="fas fa-edit"></i>
                </button>
                <button onclick="deleteEmployee(${employee.id})" class="text-red-600 hover:text-red-900">
                    <i class="fas fa-trash"></i>
                </button>
            </td>
        `;
        employeesTable.appendChild(row);
    });
}

function editEmployee(employeeId) {
    const employees = dataManager.getData('employees');
    const employee = employees.find(e => e.id === employeeId);
    if (employee) {
        openEmployeeModal(employee);
    }
}

function deleteEmployee(employeeId) {
    showConfirmation('هل أنت متأكد من حذف هذا الموظف؟', () => {
        if (dataManager.deleteItem('employees', employeeId)) {
            loadEmployees();
            showNotification('تم حذف الموظف بنجاح');
        }
    });
}