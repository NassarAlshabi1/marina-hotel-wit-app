// Payments management functions
function loadPaymentsSection() {
    const paymentsSection = document.getElementById('paymentsSection');
    paymentsSection.innerHTML = `
        <div class="flex justify-between items-center mb-6">
            <h2 class="text-2xl font-bold text-gray-800">إدارة المدفوعات</h2>
            <button onclick="openAddPaymentModal()" class="btn-primary text-white px-6 py-2 rounded-lg">
                <i class="fas fa-plus ml-2"></i>
                إضافة دفعة
            </button>
        </div>
        <div class="bg-white rounded-xl shadow-sm">
            <div class="overflow-x-auto">
                <table class="w-full table-hover">
                    <thead class="bg-gray-50">
                        <tr>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">رقم الدفعة</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">رقم الحجز</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">المبلغ</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">طريقة الدفع</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">التاريخ</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">الملاحظات</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">الإجراءات</th>
                        </tr>
                    </thead>
                    <tbody id="paymentsTable" class="divide-y divide-gray-200">
                    </tbody>
                </table>
            </div>
        </div>
    `;
    loadPayments();
}

function loadPayments() {
    const payments = dataManager.getData('payments');
    const bookings = dataManager.getData('bookings');
    const paymentsTable = document.getElementById('paymentsTable');
    if (!paymentsTable) return;
    paymentsTable.innerHTML = '';
    payments.forEach(payment => {
        const booking = bookings.find(b => b.booking_id === payment.booking_id);
        const guestName = booking ? booking.guest_name : 'غير معروف';
        const row = document.createElement('tr');
        row.innerHTML = `
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${payment.payment_id}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${payment.booking_id} - ${guestName}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${formatCurrency(payment.amount)}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${payment.payment_method}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${formatDate(payment.payment_date)}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${payment.notes}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                <button onclick="editPayment(${payment.payment_id})" class="text-blue-600 hover:text-blue-900 ml-2">
                    <i class="fas fa-edit"></i>
                </button>
                <button onclick="deletePayment(${payment.payment_id})" class="text-red-600 hover:text-red-900">
                    <i class="fas fa-trash"></i>
                </button>
            </td>
        `;
        paymentsTable.appendChild(row);
    });
}

function editPayment(paymentId) {
    const payments = dataManager.getData('payments');
    const payment = payments.find(p => p.payment_id === paymentId);
    if (payment) {
        openPaymentModal(payment);
    }
}

function deletePayment(paymentId) {
    showConfirmation('هل أنت متأكد من حذف هذه الدفعة؟', () => {
        if (dataManager.deleteItem('payments', paymentId)) {
            loadPayments();
            updateStats();
            showNotification('تم حذف الدفعة بنجاح');
        }
    });
}

const BOLT_API_BASE = '/marinahotel/bolt/api';

async function boltApiGetPaymentInfo(bookingId) {
    const res = await fetch(`${BOLT_API_BASE}/payments.php?booking_id=${encodeURIComponent(bookingId)}`, { credentials: 'same-origin' });
    const json = await res.json();
    if (!json || json.success === false) {
        const msg = (json && (json.error || json.message)) ? (json.error || json.message) : 'حدث خطأ';
        throw new Error(msg);
    }
    return json;
}

async function boltApiAddPayment(payload) {
    const body = new URLSearchParams();
    body.set('action', 'add_payment');
    body.set('booking_id', String(payload.booking_id));
    body.set('amount', String(payload.amount));
    if (payload.payment_date) body.set('payment_date', payload.payment_date);
    if (payload.payment_method) body.set('payment_method', payload.payment_method);
    if (payload.notes) body.set('notes', payload.notes);
    const res = await fetch(`${BOLT_API_BASE}/payments.php`, { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body });
    const json = await res.json();
    if (!json || json.success === false) {
        const msg = (json && (json.error || json.message)) ? (json.error || json.message) : 'فشل إضافة الدفعة';
        throw new Error(msg);
    }
    return json;
}

async function boltApiCheckout(bookingId) {
    const body = new URLSearchParams();
    body.set('action', 'checkout');
    body.set('booking_id', String(bookingId));
    const res = await fetch(`${BOLT_API_BASE}/payments.php`, { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body });
    const json = await res.json();
    if (!json || json.success === false) {
        const msg = (json && (json.error || json.message)) ? (json.error || json.message) : 'فشل تسجيل المغادرة';
        throw new Error(msg);
    }
    return json;
}

async function loadPaymentsForBooking(bookingId) {
    const data = await boltApiGetPaymentInfo(bookingId);
    const paymentsTable = document.getElementById('paymentsTable');
    if (!paymentsTable) return;
    paymentsTable.innerHTML = '';
    data.payments.forEach(p => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${p.payment_id}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${data.booking.booking_id} - ${data.booking.guest_name}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${formatCurrency(p.amount)}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${p.payment_method}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${formatDate(p.payment_date)}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${p.notes || ''}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm font-medium"></td>
        `;
        paymentsTable.appendChild(row);
    });
}

window.fetchPaymentInfo = boltApiGetPaymentInfo;
window.addPaymentViaAPI = boltApiAddPayment;
window.checkoutBooking = boltApiCheckout;
window.loadPaymentsForBooking = loadPaymentsForBooking;
