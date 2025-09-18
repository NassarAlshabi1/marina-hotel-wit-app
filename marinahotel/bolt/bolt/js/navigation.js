// Navigation functions
function initializeNavigation() {
    // Sidebar toggle
    document.getElementById('openSidebar').addEventListener('click', function() {
        document.getElementById('sidebar').classList.remove('-translate-x-full');
    });

    document.getElementById('closeSidebar').addEventListener('click', function() {
        document.getElementById('sidebar').classList.add('-translate-x-full');
    });
}

function showSection(sectionName) {
    // Hide all sections
    const sections = ['dashboard', 'rooms', 'bookings', 'payments', 'expenses', 'employees', 'reports', 'settings'];
    sections.forEach(section => {
        const sectionElement = document.getElementById(section + 'Section');
        if (sectionElement) {
            sectionElement.classList.add('hidden');
        }
    });
    
    // Show selected section
    const selectedSection = document.getElementById(sectionName + 'Section');
    if (selectedSection) {
        selectedSection.classList.remove('hidden');
    }
    
    // Update page title
    const titles = {
        dashboard: 'لوحة التحكم',
        rooms: 'إدارة الغرف',
        bookings: 'إدارة الحجوزات',
        payments: 'إدارة المدفوعات',
        expenses: 'إدارة المصروفات',
        employees: 'إدارة الموظفين',
        reports: 'التقارير المتقدمة',
        settings: 'الإعدادات'
    };
    document.getElementById('pageTitle').textContent = titles[sectionName];
    
    // Update active nav item
    document.querySelectorAll('.nav-item').forEach(item => {
        item.classList.remove('bg-blue-50', 'text-blue-600');
    });
    
    // Load section content
    loadSectionContent(sectionName);
}

function loadSectionContent(sectionName) {
    switch(sectionName) {
        case 'dashboard':
            loadDashboard();
            break;
        case 'rooms':
            loadRoomsSection();
            break;
        case 'bookings':
            loadBookingsSection();
            break;
        case 'payments':
            loadPaymentsSection();
            break;
        case 'expenses':
            loadExpensesSection();
            break;
        case 'employees':
            loadEmployeesSection();
            break;
        case 'reports':
            loadReportsSection();
            break;
        case 'settings':
            loadSettingsSection();
            break;
    }
}