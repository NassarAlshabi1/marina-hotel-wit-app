// Bookings management functions
function loadBookingsSection() {
    const bookingsSection = document.getElementById('bookingsSection');
    bookingsSection.innerHTML = `
        <div class="flex justify-between items-center mb-6">
            <h2 class="text-2xl font-bold text-gray-800">إدارة الحجوزات</h2>
            <button onclick="openAddBookingModal()" class="btn-primary text-white px-6 py-2 rounded-lg">
                <i class="fas fa-plus ml-2"></i>
                حجز جديد
            </button>
        </div>
        <div class="bg-white rounded-xl shadow-sm">
            <div class="overflow-x-auto">
                <table class="w-full table-hover">
                    <thead class="bg-gray-50">
                        <tr>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">رقم الحجز</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">اسم النزيل</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">رقم الهاتف</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">رقم الغرفة</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">تاريخ الوصول</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">عدد الليالي</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">الحالة</th>
                            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">الإجراءات</th>
                        </tr>
                    </thead>
                    <tbody id="bookingsTable" class="divide-y divide-gray-200">
                        <!-- Data will be populated here -->
                    </tbody>
                </table>
            </div>
        </div>
    `;
    
    loadBookings();
}

function loadBookings() {
    const bookings = dataManager.getData('bookings');
    const bookingsTable = document.getElementById('bookingsTable');
    if (!bookingsTable) return;
    
    bookingsTable.innerHTML = '';
    
    bookings.forEach(booking => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${booking.booking_id}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${booking.guest_name}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${booking.guest_phone}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${booking.room_number}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${formatDate(booking.checkin_date)}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${booking.calculated_nights}</td>
            <td class="px-6 py-4 whitespace-nowrap">
                <span class="px-2 py-1 text-xs rounded-full ${booking.status === 'محجوزة' ? 'status-occupied' : 'status-available'}">
                    ${booking.status}
                </span>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                <button onclick="editBooking(${booking.booking_id})" class="text-blue-600 hover:text-blue-900 ml-2">
                    <i class="fas fa-edit"></i>
                </button>
                <button onclick="checkoutBooking(${booking.booking_id})" class="text-green-600 hover:text-green-900 ml-2">
                    <i class="fas fa-sign-out-alt"></i>
                </button>
                <button onclick="deleteBooking(${booking.booking_id})" class="text-red-600 hover:text-red-900">
                    <i class="fas fa-trash"></i>
                </button>
            </td>
        `;
        bookingsTable.appendChild(row);
    });
}

function editBooking(bookingId) {
    const bookings = dataManager.getData('bookings');
    const booking = bookings.find(b => b.booking_id === bookingId);
    if (booking) {
        openBookingModal(booking);
    }
}

function deleteBooking(bookingId) {
    showConfirmation('هل أنت متأكد من حذف هذا الحجز؟', () => {
        const bookings = dataManager.getData('bookings');
        const booking = bookings.find(b => b.booking_id === bookingId);
        if (booking) {
            const rooms = dataManager.getData('rooms');
            const room = rooms.find(r => r.room_number === booking.room_number);
            if (room) {
                room.status = 'شاغرة';
                dataManager.updateItem('rooms', room.room_number, room);
            }
        }
        
        if (dataManager.deleteItem('bookings', bookingId)) {
            loadBookings();
            loadRecentBookings();
            updateStats();
            showNotification('تم حذف الحجز بنجاح');
        }
    });
}

function checkoutBooking(bookingId) {
    showConfirmation('هل أنت متأكد من تسجيل خروج هذا النزيل؟', () => {
        const bookings = dataManager.getData('bookings');
        const booking = bookings.find(b => b.booking_id === bookingId);
        if (booking) {
            booking.status = 'شاغرة';
            const rooms = dataManager.getData('rooms');
            const room = rooms.find(r => r.room_number === booking.room_number);
            if (room) {
                room.status = 'شاغرة';
                dataManager.updateItem('rooms', room.room_number, room);
            }
            dataManager.updateItem('bookings', bookingId, booking);
            loadBookings();
            loadRecentBookings();
            updateStats();
            showNotification('تم تسجيل الخروج بنجاح');
        }
    });
}