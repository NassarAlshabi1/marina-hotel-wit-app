// Reports management functions
let currentReportTab = 'revenue';

function loadReportsSection() {
    const reportsSection = document.getElementById('reportsSection');
    reportsSection.innerHTML = `
        <div class="flex justify-between items-center mb-6">
            <h2 class="text-2xl font-bold text-gray-800">التقارير المتقدمة</h2>
            <div class="flex space-x-4 space-x-reverse no-print">
                <button onclick="exportData()" class="bg-green-600 text-white px-4 py-2 rounded-lg hover:bg-green-700 transition-colors">
                    <i class="fas fa-download ml-2"></i>
                    تصدير البيانات
                </button>
                <button onclick="importData()" class="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700 transition-colors">
                    <i class="fas fa-upload ml-2"></i>
                    استيراد البيانات
                </button>
                <button onclick="printReport()" class="bg-purple-600 text-white px-4 py-2 rounded-lg hover:bg-purple-700 transition-colors">
                    <i class="fas fa-print ml-2"></i>
                    طباعة التقرير
                </button>
            </div>
        </div>

        <!-- Report Tabs -->
        <div class="flex space-x-4 space-x-reverse mb-6 no-print">
            <button onclick="showReportTab('revenue')" class="tab-button active" id="revenueTab">
                <i class="fas fa-chart-line ml-2"></i>
                تقرير الإيرادات
            </button>
            <button onclick="showReportTab('occupancy')" class="tab-button" id="occupancyTab">
                <i class="fas fa-bed ml-2"></i>
                تقرير الإشغال
            </button>
            <button onclick="showReportTab('expenses')" class="tab-button" id="expensesTab">
                <i class="fas fa-receipt ml-2"></i>
                تقرير المصروفات
            </button>
            <button onclick="showReportTab('financial')" class="tab-button" id="financialTab">
                <i class="fas fa-calculator ml-2"></i>
                التقرير المالي
            </button>
        </div>

        <!-- Date Range Selector -->
        <div class="bg-white p-4 rounded-xl shadow-sm mb-6 no-print">
            <div class="flex items-center space-x-4 space-x-reverse">
                <div class="flex space-x-2 space-x-reverse">
                    <button onclick="setDateRange('today')" class="px-4 py-2 bg-blue-100 text-blue-700 rounded-lg hover:bg-blue-200 transition-colors">اليوم</button>
                    <button onclick="setDateRange('week')" class="px-4 py-2 bg-blue-100 text-blue-700 rounded-lg hover:bg-blue-200 transition-colors">هذا الأسبوع</button>
                    <button onclick="setDateRange('month')" class="px-4 py-2 bg-blue-100 text-blue-700 rounded-lg hover:bg-blue-200 transition-colors">هذا الشهر</button>
                    <button onclick="setDateRange('year')" class="px-4 py-2 bg-blue-100 text-blue-700 rounded-lg hover:bg-blue-200 transition-colors">هذا العام</button>
                </div>
                <div class="flex items-center space-x-4 space-x-reverse">
                    <label class="text-sm font-medium text-gray-700">من:</label>
                    <input type="date" id="startDate" class="px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500">
                    <label class="text-sm font-medium text-gray-700">إلى:</label>
                    <input type="date" id="endDate" class="px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500">
                    <button onclick="generateReport()" class="btn-primary text-white px-4 py-2 rounded-lg">
                        <i class="fas fa-chart-bar ml-2"></i>
                        إنشاء التقرير
                    </button>
                </div>
            </div>
        </div>

        <!-- Report Content -->
        <div id="reportContent">
            <!-- Reports will be loaded here -->
        </div>
    `;
    
    setDefaultDates();
    generateReport();
}

function showReportTab(tabName) {
    // Update tab buttons
    document.querySelectorAll('.tab-button').forEach(btn => {
        btn.classList.remove('active');
    });
    const tabButton = document.getElementById(tabName + 'Tab');
    if (tabButton) {
        tabButton.classList.add('active');
    }
    
    currentReportTab = tabName;
    generateReport();
}

function setDateRange(range) {
    const now = new Date();
    const startDate = document.getElementById('startDate');
    const endDate = document.getElementById('endDate');
    
    if (!startDate || !endDate) return;
    
    switch(range) {
        case 'today':
            startDate.value = now.toISOString().slice(0, 10);
            endDate.value = now.toISOString().slice(0, 10);
            break;
        case 'week':
            const weekStart = new Date(now.setDate(now.getDate() - now.getDay()));
            startDate.value = weekStart.toISOString().slice(0, 10);
            endDate.value = new Date().toISOString().slice(0, 10);
            break;
        case 'month':
            const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
            startDate.value = monthStart.toISOString().slice(0, 10);
            endDate.value = new Date().toISOString().slice(0, 10);
            break;
        case 'year':
            const yearStart = new Date(now.getFullYear(), 0, 1);
            startDate.value = yearStart.toISOString().slice(0, 10);
            endDate.value = new Date().toISOString().slice(0, 10);
            break;
    }
    generateReport();
}

function generateReport() {
    const startDateEl = document.getElementById('startDate');
    const endDateEl = document.getElementById('endDate');
    
    if (!startDateEl || !endDateEl) return;
    
    const startDate = startDateEl.value;
    const endDate = endDateEl.value;
    
    // Filter data based on date range
    const payments = dataManager.getData('payments');
    const expenses = dataManager.getData('expenses');
    
    const filteredPayments = payments.filter(payment => {
        if (!startDate || !endDate) return true;
        return payment.payment_date >= startDate && payment.payment_date <= endDate;
    });
    
    const filteredExpenses = expenses.filter(expense => {
        if (!startDate || !endDate) return true;
        return expense.date >= startDate && expense.date <= endDate;
    });
    
    // Generate specific report based on current tab
    switch(currentReportTab) {
        case 'revenue':
            generateRevenueReport(filteredPayments, startDate, endDate);
            break;
        case 'occupancy':
            generateOccupancyReport();
            break;
        case 'expenses':
            generateExpensesReport(filteredExpenses, startDate, endDate);
            break;
        case 'financial':
            generateFinancialReport(filteredPayments, filteredExpenses, startDate, endDate);
            break;
    }
}

function generateRevenueReport(payments, startDate, endDate) {
    const totalRevenue = payments.reduce((sum, payment) => sum + payment.amount, 0);
    const totalPayments = payments.length;
    const avgPayment = totalPayments > 0 ? Math.round(totalRevenue / totalPayments) : 0;
    
    const dateRangeText = startDate && endDate ? 
        `الفترة: من ${startDate} إلى ${endDate}` : 
        'الفترة: جميع البيانات';
    
    const reportContent = document.getElementById('reportContent');
    reportContent.innerHTML = `
        <div class="report-card">
            <div class="flex justify-between items-center mb-6">
                <h3 class="text-xl font-bold text-gray-800">تقرير الإيرادات التفصيلي</h3>
                <div class="text-sm text-gray-600">${dateRangeText}</div>
            </div>

            <!-- Revenue Summary -->
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
                <div class="bg-gradient-to-r from-blue-500 to-blue-600 text-white p-4 rounded-lg">
                    <div class="text-sm opacity-90">إجمالي الإيرادات</div>
                    <div class="text-2xl font-bold">${totalRevenue.toLocaleString()}</div>
                    <div class="text-xs opacity-75">ريال يمني</div>
                </div>
                <div class="bg-gradient-to-r from-green-500 to-green-600 text-white p-4 rounded-lg">
                    <div class="text-sm opacity-90">عدد المدفوعات</div>
                    <div class="text-2xl font-bold">${totalPayments}</div>
                    <div class="text-xs opacity-75">دفعة</div>
                </div>
                <div class="bg-gradient-to-r from-purple-500 to-purple-600 text-white p-4 rounded-lg">
                    <div class="text-sm opacity-90">متوسط الدفعة</div>
                    <div class="text-2xl font-bold">${avgPayment.toLocaleString()}</div>
                    <div class="text-xs opacity-75">ريال يمني</div>
                </div>
            </div>

            <!-- Revenue Chart -->
            <div class="chart-container">
                <canvas id="detailedRevenueChart"></canvas>
            </div>
        </div>
    `;
    
    // Generate chart after DOM is updated
    setTimeout(() => {
        generateDetailedRevenueChart(payments);
    }, 100);
}

function generateDetailedRevenueChart(payments) {
    const ctx = document.getElementById('detailedRevenueChart');
    if (!ctx) return;
    
    // Group payments by date
    const revenueByDate = {};
    payments.forEach(payment => {
        const date = payment.payment_date;
        revenueByDate[date] = (revenueByDate[date] || 0) + payment.amount;
    });
    
    const dates = Object.keys(revenueByDate).sort();
    const revenues = dates.map(date => revenueByDate[date]);
    
    new Chart(ctx.getContext('2d'), {
        type: 'bar',
        data: {
            labels: dates,
            datasets: [{
                label: 'الإيرادات اليومية',
                data: revenues,
                backgroundColor: 'rgba(59, 130, 246, 0.8)',
                borderColor: 'rgb(59, 130, 246)',
                borderWidth: 1
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    ticks: {
                        callback: function(value) {
                            return value.toLocaleString() + ' ريال';
                        }
                    }
                }
            }
        }
    });
}

function generateOccupancyReport() {
    const rooms = dataManager.getData('rooms');
    const totalRooms = rooms.length;
    const occupiedRooms = rooms.filter(room => room.status === 'محجوزة').length;
    const availableRooms = totalRooms - occupiedRooms;
    const occupancyRate = Math.round((occupiedRooms / totalRooms) * 100);
    
    const reportContent = document.getElementById('reportContent');
    reportContent.innerHTML = `
        <div class="report-card">
            <div class="flex justify-between items-center mb-6">
                <h3 class="text-xl font-bold text-gray-800">تقرير الإشغال التفصيلي</h3>
            </div>

            <!-- Occupancy Summary -->
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
                <div class="bg-gradient-to-r from-red-500 to-red-600 text-white p-4 rounded-lg">
                    <div class="text-sm opacity-90">معدل الإشغال</div>
                    <div class="text-2xl font-bold">${occupancyRate}%</div>
                    <div class="text-xs opacity-75">من إجمالي الغرف</div>
                </div>
                <div class="bg-gradient-to-r from-blue-500 to-blue-600 text-white p-4 rounded-lg">
                    <div class="text-sm opacity-90">الغرف المحجوزة</div>
                    <div class="text-2xl font-bold">${occupiedRooms}</div>
                    <div class="text-xs opacity-75">غرفة</div>
                </div>
                <div class="bg-gradient-to-r from-green-500 to-green-600 text-white p-4 rounded-lg">
                    <div class="text-sm opacity-90">الغرف الشاغرة</div>
                    <div class="text-2xl font-bold">${availableRooms}</div>
                    <div class="text-xs opacity-75">غرفة</div>
                </div>
            </div>

            <!-- Room Status Details -->
            <div class="mt-6">
                <h4 class="text-lg font-semibold text-gray-800 mb-4">تفاصيل حالة الغرف</h4>
                <div class="overflow-x-auto">
                    <table class="w-full table-hover">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">رقم الغرفة</th>
                                <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">نوع الغرفة</th>
                                <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">السعر</th>
                                <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">الحالة</th>
                                <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">النزيل الحالي</th>
                            </tr>
                        </thead>
                        <tbody id="roomStatusTable" class="divide-y divide-gray-200">
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    `;
    
    // Populate room status table
    const roomStatusTable = document.getElementById('roomStatusTable');
    const bookings = dataManager.getData('bookings');
    
    rooms.forEach(room => {
        const booking = bookings.find(b => 
            b.room_number === room.room_number && b.status === 'محجوزة'
        );
        const guestName = booking ? booking.guest_name : '-';
        
        const row = document.createElement('tr');
        row.innerHTML = `
            <td class="px-4 py-3 text-sm text-gray-900">${room.room_number}</td>
            <td class="px-4 py-3 text-sm text-gray-900">${room.type}</td>
            <td class="px-4 py-3 text-sm text-gray-900">${formatCurrency(room.price)}</td>
            <td class="px-4 py-3">
                <span class="px-2 py-1 text-xs rounded-full ${room.status === 'محجوزة' ? 'status-occupied' : 'status-available'}">
                    ${room.status}
                </span>
            </td>
            <td class="px-4 py-3 text-sm text-gray-900">${guestName}</td>
        `;
        roomStatusTable.appendChild(row);
    });
}

function generateExpensesReport(expenses, startDate, endDate) {
    const totalExpenses = expenses.reduce((sum, expense) => sum + expense.amount, 0);
    const totalExpenseCount = expenses.length;
    const maxExpense = expenses.length > 0 ? Math.max(...expenses.map(e => e.amount)) : 0;
    
    const dateRangeText = startDate && endDate ? 
        `الفترة: من ${startDate} إلى ${endDate}` : 
        'الفترة: جميع البيانات';
    
    const reportContent = document.getElementById('reportContent');
    reportContent.innerHTML = `
        <div class="report-card">
            <div class="flex justify-between items-center mb-6">
                <h3 class="text-xl font-bold text-gray-800">تقرير المصروفات التفصيلي</h3>
                <div class="text-sm text-gray-600">${dateRangeText}</div>
            </div>

            <!-- Expenses Summary -->
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
                <div class="bg-gradient-to-r from-red-500 to-red-600 text-white p-4 rounded-lg">
                    <div class="text-sm opacity-90">إجمالي المصروفات</div>
                    <div class="text-2xl font-bold">${totalExpenses.toLocaleString()}</div>
                    <div class="text-xs opacity-75">ريال يمني</div>
                </div>
                <div class="bg-gradient-to-r from-purple-500 to-purple-600 text-white p-4 rounded-lg">
                    <div class="text-sm opacity-90">عدد المصروفات</div>
                    <div class="text-2xl font-bold">${totalExpenseCount}</div>
                    <div class="text-xs opacity-75">مصروف</div>
                </div>
                <div class="bg-gradient-to-r from-blue-500 to-blue-600 text-white p-4 rounded-lg">
                    <div class="text-sm opacity-90">أكبر مصروف</div>
                    <div class="text-2xl font-bold">${maxExpense.toLocaleString()}</div>
                    <div class="text-xs opacity-75">ريال يمني</div>
                </div>
            </div>

            <!-- Detailed Expenses Table -->
            <div class="mt-6">
                <h4 class="text-lg font-semibold text-gray-800 mb-4">تفاصيل المصروفات</h4>
                <div class="overflow-x-auto">
                    <table class="w-full table-hover">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">التاريخ</th>
                                <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">النوع</th>
                                <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">الوصف</th>
                                <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">المبلغ</th>
                            </tr>
                        </thead>
                        <tbody id="detailedExpensesTable" class="divide-y divide-gray-200">
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    `;
    
    // Populate expenses table
    const detailedExpensesTable = document.getElementById('detailedExpensesTable');
    const expenseTypes = {
        'utilities': 'مرافق',
        'purchases': 'مشتريات',
        'maintenance': 'صيانة',
        'salaries': 'رواتب',
        'other': 'أخرى'
    };
    
    // Sort expenses by date (newest first)
    const sortedExpenses = [...expenses].sort((a, b) => new Date(b.date) - new Date(a.date));
    
    sortedExpenses.forEach(expense => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td class="px-4 py-3 text-sm text-gray-900">${formatDate(expense.date)}</td>
            <td class="px-4 py-3 text-sm text-gray-900">${expenseTypes[expense.expense_type] || expense.expense_type}</td>
            <td class="px-4 py-3 text-sm text-gray-900">${expense.description}</td>
            <td class="px-4 py-3 text-sm text-gray-900">${formatCurrency(expense.amount)}</td>
        `;
        detailedExpensesTable.appendChild(row);
    });
}

function generateFinancialReport(payments, expenses, startDate, endDate) {
    const totalRevenue = payments.reduce((sum, payment) => sum + payment.amount, 0);
    const totalExpenses = expenses.reduce((sum, expense) => sum + expense.amount, 0);
    const netProfit = totalRevenue - totalExpenses;
    const profitMargin = totalRevenue > 0 ? Math.round((netProfit / totalRevenue) * 100) : 0;
    
    const dateRangeText = startDate && endDate ? 
        `الفترة: من ${startDate} إلى ${endDate}` : 
        'الفترة: جميع البيانات';
    
    const reportContent = document.getElementById('reportContent');
    reportContent.innerHTML = `
        <div class="report-card">
            <div class="flex justify-between items-center mb-6">
                <h3 class="text-xl font-bold text-gray-800">التقرير المالي الشامل</h3>
                <div class="text-sm text-gray-600">${dateRangeText}</div>
            </div>

            <!-- Financial Summary -->
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
                <div class="bg-gradient-to-r from-green-500 to-green-600 text-white p-6 rounded-lg">
                    <div class="text-sm opacity-90">إجمالي الإيرادات</div>
                    <div class="text-3xl font-bold">${totalRevenue.toLocaleString()}</div>
                    <div class="text-xs opacity-75">ريال يمني</div>
                </div>
                <div class="bg-gradient-to-r from-red-500 to-red-600 text-white p-6 rounded-lg">
                    <div class="text-sm opacity-90">إجمالي المصروفات</div>
                    <div class="text-3xl font-bold">${totalExpenses.toLocaleString()}</div>
                    <div class="text-xs opacity-75">ريال يمني</div>
                </div>
                <div class="bg-gradient-to-r from-blue-500 to-blue-600 text-white p-6 rounded-lg">
                    <div class="text-sm opacity-90">صافي الربح</div>
                    <div class="text-3xl font-bold">${netProfit.toLocaleString()}</div>
                    <div class="text-xs opacity-75">ريال يمني</div>
                </div>
            </div>

            <!-- Profit Margin -->
            <div class="bg-white border border-gray-200 rounded-lg p-4 mb-6">
                <div class="flex justify-between items-center">
                    <span class="text-lg font-semibold text-gray-800">هامش الربح</span>
                    <span class="text-2xl font-bold text-blue-600">${profitMargin}%</span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-3 mt-2">
                    <div class="bg-blue-600 h-3 rounded-full transition-all duration-500" style="width: ${Math.max(0, Math.min(100, profitMargin))}%"></div>
                </div>
            </div>
        </div>
    `;
}

function exportData() {
    const dataStr = dataManager.exportData();
    const dataBlob = new Blob([dataStr], {type: 'application/json'});
    const url = URL.createObjectURL(dataBlob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `hotel_data_backup_${new Date().toISOString().slice(0, 10)}.json`;
    link.click();
    URL.revokeObjectURL(url);
    showNotification('تم تصدير البيانات بنجاح');
}

function importData() {
    document.getElementById('fileInput').click();
}

function printReport() {
    window.print();
}