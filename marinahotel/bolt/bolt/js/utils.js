// Utility functions
function showNotification(message, type = 'success') {
    const notification = document.getElementById('notification');
    notification.textContent = message;
    notification.className = `notification ${type} show`;
    
    setTimeout(() => {
        notification.classList.remove('show');
    }, 3000);
}

function updateDateTime() {
    const now = new Date();
    const options = {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        timeZone: 'Asia/Aden'
    };
    document.getElementById('currentDateTime').textContent = now.toLocaleDateString('ar-YE', options);
}

function setDefaultDates() {
    const now = new Date();
    const localDateTime = new Date(now.getTime() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
    const localDate = new Date(now.getTime() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
    
    const checkinDate = document.getElementById('checkinDate');
    const paymentDate = document.getElementById('paymentDate');
    const expenseDate = document.getElementById('expenseDate');
    const startDate = document.getElementById('startDate');
    const endDate = document.getElementById('endDate');
    
    if (checkinDate) checkinDate.value = localDateTime;
    if (paymentDate) paymentDate.value = localDateTime;
    if (expenseDate) expenseDate.value = localDate;
    if (startDate) startDate.value = localDate;
    if (endDate) endDate.value = localDate;
}

function formatCurrency(amount) {
    return amount.toLocaleString() + ' ريال';
}

function formatDate(dateString) {
    const date = new Date(dateString);
    return date.toLocaleDateString('ar-YE');
}

function generateId(items, idField = 'id') {
    if (!items || items.length === 0) return 1;
    return Math.max(...items.map(item => item[idField] || 0)) + 1;
}