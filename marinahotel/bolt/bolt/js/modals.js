// Modal management functions
let currentEditId = null;
let currentEditType = null;

function initializeModals() {
    const modalsContainer = document.getElementById('modalsContainer');
    modalsContainer.innerHTML = `
        <!-- Add/Edit Room Modal -->
        <div id="roomModal" class="fixed inset-0 bg-black bg-opacity-50 hidden items-center justify-center z-50 modal">
            <div class="bg-white rounded-xl p-6 w-full max-w-md animate-fade-in">
                <div class="flex justify-between items-center mb-4">
                    <h3 id="roomModalTitle" class="text-lg font-semibold text-gray-800">إضافة غرفة جديدة</h3>
                    <button onclick="closeModal('roomModal')" class="text-gray-500 hover:text-gray-700">
                        <i class="fas fa-times"></i>
                    </button>
                </div>
                <form id="roomForm" class="space-y-4">
                    <input type="hidden" id="roomId" name="room_id">
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">رقم الغرفة</label>
                        <input type="text" id="roomNumber" name="room_number" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">نوع الغرفة</label>
                        <select id="roomType" name="type" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                            <option value="">اختر نوع الغرفة</option>
                            <option value="سرير فردي">سرير فردي</option>
                            <option value="سرير عائلي">سرير عائلي</option>
                        </select>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">السعر (ريال يمني)</label>
                        <input type="number" id="roomPrice" name="price" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                    </div>
                    <div class="flex space-x-4 space-x-reverse">
                        <button type="submit" class="flex-1 bg-blue-600 text-white py-2 rounded-lg hover:bg-blue-700 transition-colors">
                            <span id="roomSubmitText">إضافة</span>
                        </button>
                        <button type="button" onclick="closeModal('roomModal')" class="flex-1 bg-gray-300 text-gray-700 py-2 rounded-lg hover:bg-gray-400 transition-colors">
                            إلغاء
                        </button>
                    </div>
                </form>
            </div>
        </div>

        <!-- Add/Edit Booking Modal -->
        <div id="bookingModal" class="fixed inset-0 bg-black bg-opacity-50 hidden items-center justify-center z-50 modal">
            <div class="bg-white rounded-xl p-6 w-full max-w-2xl animate-fade-in max-h-screen overflow-y-auto">
                <div class="flex justify-between items-center mb-4">
                    <h3 id="bookingModalTitle" class="text-lg font-semibold text-gray-800">حجز جديد</h3>
                    <button onclick="closeModal('bookingModal')" class="text-gray-500 hover:text-gray-700">
                        <i class="fas fa-times"></i>
                    </button>
                </div>
                <form id="bookingForm" class="space-y-4">
                    <input type="hidden" id="bookingId" name="booking_id">
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-2">اسم النزيل</label>
                            <input type="text" id="guestName" name="guest_name" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-2">رقم الهاتف</label>
                            <input type="text" id="guestPhone" name="guest_phone" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-2">نوع الهوية</label>
                            <select id="guestIdType" name="guest_id_type" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                                <option value="">اختر نوع الهوية</option>
                                <option value="بطاقة شخصية">بطاقة شخصية</option>
                                <option value="رخصة قيادة">رخصة قيادة</option>
                                <option value="جواز سفر">جواز سفر</option>
                            </select>
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-2">رقم الهوية</label>
                            <input type="text" id="guestIdNumber" name="guest_id_number" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-2">الجنسية</label>
                            <input type="text" id="guestNationality" name="guest_nationality" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" value="يمني">
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-2">رقم الغرفة</label>
                            <select id="bookingRoomNumber" name="room_number" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                                <option value="">اختر الغرفة</option>
                            </select>
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-2">تاريخ الوصول</label>
                            <input type="datetime-local" id="checkinDate" name="checkin_date" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-2">عدد الليالي المتوقع</label>
                            <input type="number" id="expectedNights" name="expected_nights" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" value="1" min="1">
                        </div>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">الملاحظات</label>
                        <textarea id="bookingNotes" name="notes" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" rows="3"></textarea>
                    </div>
                    <div class="flex space-x-4 space-x-reverse">
                        <button type="submit" class="flex-1 bg-blue-600 text-white py-2 rounded-lg hover:bg-blue-700 transition-colors">
                            <span id="bookingSubmitText">إضافة الحجز</span>
                        </button>
                        <button type="button" onclick="closeModal('bookingModal')" class="flex-1 bg-gray-300 text-gray-700 py-2 rounded-lg hover:bg-gray-400 transition-colors">
                            إلغاء
                        </button>
                    </div>
                </form>
            </div>
        </div>

        <!-- Add/Edit Payment Modal -->
        <div id="paymentModal" class="fixed inset-0 bg-black bg-opacity-50 hidden items-center justify-center z-50 modal">
            <div class="bg-white rounded-xl p-6 w-full max-w-md animate-fade-in">
                <div class="flex justify-between items-center mb-4">
                    <h3 id="paymentModalTitle" class="text-lg font-semibold text-gray-800">إضافة دفعة جديدة</h3>
                    <button onclick="closeModal('paymentModal')" class="text-gray-500 hover:text-gray-700">
                        <i class="fas fa-times"></i>
                    </button>
                </div>
                <form id="paymentForm" class="space-y-4">
                    <input type="hidden" id="paymentId" name="payment_id">
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">رقم الحجز</label>
                        <select id="paymentBookingId" name="booking_id" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                            <option value="">اختر الحجز</option>
                        </select>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">المبلغ (ريال يمني)</label>
                        <input type="number" id="paymentAmount" name="amount" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">طريقة الدفع</label>
                        <select id="paymentMethod" name="payment_method" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                            <option value="">اختر طريقة الدفع</option>
                            <option value="نقدي">نقدي</option>
                            <option value="بطاقة ائتمان">بطاقة ائتمان</option>
                            <option value="تحويل بنكي">تحويل بنكي</option>
                        </select>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">تاريخ الدفع</label>
                        <input type="datetime-local" id="paymentDate" name="payment_date" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">الملاحظات</label>
                        <textarea id="paymentNotes" name="notes" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" rows="3"></textarea>
                    </div>
                    <div class="flex space-x-4 space-x-reverse">
                        <button type="submit" class="flex-1 bg-blue-600 text-white py-2 rounded-lg hover:bg-blue-700 transition-colors">
                            <span id="paymentSubmitText">إضافة</span>
                        </button>
                        <button type="button" onclick="closeModal('paymentModal')" class="flex-1 bg-gray-300 text-gray-700 py-2 rounded-lg hover:bg-gray-400 transition-colors">
                            إلغاء
                        </button>
                    </div>
                </form>
            </div>
        </div>

        <!-- Add/Edit Expense Modal -->
        <div id="expenseModal" class="fixed inset-0 bg-black bg-opacity-50 hidden items-center justify-center z-50 modal">
            <div class="bg-white rounded-xl p-6 w-full max-w-md animate-fade-in">
                <div class="flex justify-between items-center mb-4">
                    <h3 id="expenseModalTitle" class="text-lg font-semibold text-gray-800">إضافة مصروف جديد</h3>
                    <button onclick="closeModal('expenseModal')" class="text-gray-500 hover:text-gray-700">
                        <i class="fas fa-times"></i>
                    </button>
                </div>
                <form id="expenseForm" class="space-y-4">
                    <input type="hidden" id="expenseId" name="expense_id">
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">نوع المصروف</label>
                        <select id="expenseType" name="expense_type" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                            <option value="">اختر نوع المصروف</option>
                            <option value="utilities">مرافق</option>
                            <option value="purchases">مشتريات</option>
                            <option value="maintenance">صيانة</option>
                            <option value="salaries">رواتب</option>
                            <option value="other">أخرى</option>
                        </select>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">الوصف</label>
                        <input type="text" id="expenseDescription" name="description" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">المبلغ (ريال يمني)</label>
                        <input type="number" id="expenseAmount" name="amount" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">التاريخ</label>
                        <input type="date" id="expenseDate" name="date" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                    </div>
                    <div class="flex space-x-4 space-x-reverse">
                        <button type="submit" class="flex-1 bg-blue-600 text-white py-2 rounded-lg hover:bg-blue-700 transition-colors">
                            <span id="expenseSubmitText">إضافة</span>
                        </button>
                        <button type="button" onclick="closeModal('expenseModal')" class="flex-1 bg-gray-300 text-gray-700 py-2 rounded-lg hover:bg-gray-400 transition-colors">
                            إلغاء
                        </button>
                    </div>
                </form>
            </div>
        </div>

        <!-- Add/Edit Employee Modal -->
        <div id="employeeModal" class="fixed inset-0 bg-black bg-opacity-50 hidden items-center justify-center z-50 modal">
            <div class="bg-white rounded-xl p-6 w-full max-w-md animate-fade-in">
                <div class="flex justify-between items-center mb-4">
                    <h3 id="employeeModalTitle" class="text-lg font-semibold text-gray-800">إضافة موظف جديد</h3>
                    <button onclick="closeModal('employeeModal')" class="text-gray-500 hover:text-gray-700">
                        <i class="fas fa-times"></i>
                    </button>
                </div>
                <form id="employeeForm" class="space-y-4">
                    <input type="hidden" id="employeeId" name="employee_id">
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">اسم الموظف</label>
                        <input type="text" id="employeeName" name="name" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">الراتب الأساسي (ريال يمني)</label>
                        <input type="number" id="employeeSalary" name="basic_salary" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" value="0">
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">الحالة</label>
                        <select id="employeeStatus" name="status" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" required>
                            <option value="active">نشط</option>
                            <option value="inactive">غير نشط</option>
                        </select>
                    </div>
                    <div class="flex space-x-4 space-x-reverse">
                        <button type="submit" class="flex-1 bg-blue-600 text-white py-2 rounded-lg hover:bg-blue-700 transition-colors">
                            <span id="employeeSubmitText">إضافة</span>
                        </button>
                        <button type="button" onclick="closeModal('employeeModal')" class="flex-1 bg-gray-300 text-gray-700 py-2 rounded-lg hover:bg-gray-400 transition-colors">
                            إلغاء
                        </button>
                    </div>
                </form>
            </div>
        </div>

        <!-- Confirmation Modal -->
        <div id="confirmModal" class="fixed inset-0 bg-black bg-opacity-50 hidden items-center justify-center z-50 modal">
            <div class="bg-white rounded-xl p-6 w-full max-w-md animate-fade-in">
                <div class="text-center">
                    <i class="fas fa-exclamation-triangle text-4xl text-yellow-500 mb-4"></i>
                    <h3 class="text-lg font-semibold text-gray-800 mb-2">تأكيد العملية</h3>
                    <p id="confirmMessage" class="text-gray-600 mb-6">هل أنت متأكد من هذا الإجراء؟</p>
                    <div class="flex space-x-4 space-x-reverse">
                        <button id="confirmYes" class="flex-1 bg-red-600 text-white py-2 rounded-lg hover:bg-red-700 transition-colors">
                            نعم
                        </button>
                        <button id="confirmNo" class="flex-1 bg-gray-300 text-gray-700 py-2 rounded-lg hover:bg-gray-400 transition-colors">
                            إلغاء
                        </button>
                    </div>
                </div>
            </div>
        </div>
    `;
    
    initializeModalForms();
}

function initializeModalForms() {
    // Room form
    document.getElementById('roomForm').addEventListener('submit', function(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        
        if (currentEditId) {
            // Edit existing room
            const rooms = dataManager.getData('rooms');
            const room = rooms.find(r => r.room_number === currentEditId);
            if (room) {
                room.room_number = formData.get('room_number');
                room.type = formData.get('type');
                room.price = parseInt(formData.get('price'));
                dataManager.updateItem('rooms', currentEditId, room);
                showNotification('تم تعديل الغرفة بنجاح');
            }
        } else {
            // Add new room
            const rooms = dataManager.getData('rooms');
            const newRoom = {
                room_number: formData.get('room_number'),
                type: formData.get('type'),
                price: parseInt(formData.get('price')),
                status: 'شاغرة'
            };
            
            // Check if room number already exists
            if (rooms.find(r => r.room_number === newRoom.room_number)) {
                showNotification('رقم الغرفة موجود مسبقاً', 'error');
                return;
            }
            
            dataManager.addItem('rooms', newRoom);
            showNotification('تم إضافة الغرفة بنجاح');
        }
        
        loadRooms();
        updateStats();
        closeModal('roomModal');
    });

    // Booking form
    document.getElementById('bookingForm').addEventListener('submit', function(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        
        if (currentEditId) {
            // Edit existing booking
            const bookings = dataManager.getData('bookings');
            const booking = bookings.find(b => b.booking_id === currentEditId);
            if (booking) {
                // Update room status if room changed
                if (booking.room_number !== formData.get('room_number')) {
                    const rooms = dataManager.getData('rooms');
                    const oldRoom = rooms.find(r => r.room_number === booking.room_number);
                    if (oldRoom) {
                        oldRoom.status = 'شاغرة';
                        dataManager.updateItem('rooms', oldRoom.room_number, oldRoom);
                    }
                    
                    const newRoom = rooms.find(r => r.room_number === formData.get('room_number'));
                    if (newRoom) {
                        newRoom.status = 'محجوزة';
                        dataManager.updateItem('rooms', newRoom.room_number, newRoom);
                    }
                }
                
                booking.guest_name = formData.get('guest_name');
                booking.guest_phone = formData.get('guest_phone');
                booking.guest_id_type = formData.get('guest_id_type');
                booking.guest_id_number = formData.get('guest_id_number');
                booking.guest_nationality = formData.get('guest_nationality');
                booking.room_number = formData.get('room_number');
                booking.checkin_date = formData.get('checkin_date').split('T')[0];
                booking.expected_nights = parseInt(formData.get('expected_nights'));
                booking.calculated_nights = parseInt(formData.get('expected_nights'));
                booking.notes = formData.get('notes');
                
                dataManager.updateItem('bookings', currentEditId, booking);
                showNotification('تم تعديل الحجز بنجاح');
            }
        } else {
            // Add new booking
            const bookings = dataManager.getData('bookings');
            const maxId = generateId(bookings, 'booking_id');
            const newBooking = {
                booking_id: maxId,
                guest_name: formData.get('guest_name'),
                guest_phone: formData.get('guest_phone'),
                guest_id_type: formData.get('guest_id_type'),
                guest_id_number: formData.get('guest_id_number'),
                guest_nationality: formData.get('guest_nationality'),
                room_number: formData.get('room_number'),
                checkin_date: formData.get('checkin_date').split('T')[0],
                calculated_nights: parseInt(formData.get('expected_nights')),
                expected_nights: parseInt(formData.get('expected_nights')),
                status: 'محجوزة',
                notes: formData.get('notes')
            };
            
            // Update room status
            const rooms = dataManager.getData('rooms');
            const room = rooms.find(r => r.room_number === newBooking.room_number);
            if (room) {
                room.status = 'محجوزة';
                dataManager.updateItem('rooms', room.room_number, room);
            }
            
            dataManager.addItem('bookings', newBooking);
            showNotification('تم إضافة الحجز بنجاح');
        }
        
        loadBookings();
        loadRooms();
        loadRecentBookings();
        updateStats();
        closeModal('bookingModal');
    });

    // Payment form
    document.getElementById('paymentForm').addEventListener('submit', function(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        
        if (currentEditId) {
            // Edit existing payment
            const payments = dataManager.getData('payments');
            const payment = payments.find(p => p.payment_id === currentEditId);
            if (payment) {
                payment.booking_id = parseInt(formData.get('booking_id'));
                payment.amount = parseInt(formData.get('amount'));
                payment.payment_method = formData.get('payment_method');
                payment.payment_date = formData.get('payment_date').split('T')[0];
                payment.notes = formData.get('notes');
                
                dataManager.updateItem('payments', currentEditId, payment);
                showNotification('تم تعديل الدفعة بنجاح');
            }
        } else {
            const payload = {
                booking_id: parseInt(formData.get('booking_id')),
                amount: parseFloat(formData.get('amount')),
                payment_method: formData.get('payment_method'),
                payment_date: formData.get('payment_date'),
                notes: formData.get('notes')
            };
            addPaymentViaAPI(payload)
                .then(resp => {
                    showNotification(resp.message || 'تم تسجيل الدفعة بنجاح');
                    if (window.loadPaymentsForBooking) {
                        loadPaymentsForBooking(payload.booking_id);
                    }
                })
                .catch(err => {
                    showNotification(err.message || 'فشل في إضافة الدفعة', 'error');
                });
        }
        
        loadPayments();
        updateStats();
        closeModal('paymentModal');
    });

    // Expense form
    document.getElementById('expenseForm').addEventListener('submit', function(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        
        if (currentEditId) {
            // Edit existing expense
            const expenses = dataManager.getData('expenses');
            const expense = expenses.find(e => e.id === currentEditId);
            if (expense) {
                expense.expense_type = formData.get('expense_type');
                expense.description = formData.get('description');
                expense.amount = parseInt(formData.get('amount'));
                expense.date = formData.get('date');
                
                dataManager.updateItem('expenses', currentEditId, expense);
                showNotification('تم تعديل المصروف بنجاح');
            }
        } else {
            // Add new expense
            const expenses = dataManager.getData('expenses');
            const maxId = generateId(expenses);
            const newExpense = {
                id: maxId,
                expense_type: formData.get('expense_type'),
                description: formData.get('description'),
                amount: parseInt(formData.get('amount')),
                date: formData.get('date')
            };
            
            dataManager.addItem('expenses', newExpense);
            showNotification('تم إضافة المصروف بنجاح');
        }
        
        loadExpenses();
        closeModal('expenseModal');
    });

    // Employee form
    document.getElementById('employeeForm').addEventListener('submit', function(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        
        if (currentEditId) {
            // Edit existing employee
            const employees = dataManager.getData('employees');
            const employee = employees.find(e => e.id === currentEditId);
            if (employee) {
                employee.name = formData.get('name');
                employee.basic_salary = parseInt(formData.get('basic_salary'));
                employee.status = formData.get('status');
                
                dataManager.updateItem('employees', currentEditId, employee);
                showNotification('تم تعديل الموظف بنجاح');
            }
        } else {
            // Add new employee
            const employees = dataManager.getData('employees');
            const maxId = generateId(employees);
            const newEmployee = {
                id: maxId,
                name: formData.get('name'),
                basic_salary: parseInt(formData.get('basic_salary')),
                status: formData.get('status')
            };
            
            dataManager.addItem('employees', newEmployee);
            showNotification('تم إضافة الموظف بنجاح');
        }
        
        loadEmployees();
        closeModal('employeeModal');
    });
}

// Modal opening functions
function openAddRoomModal() {
    openRoomModal();
}

function openRoomModal(room = null) {
    resetRoomForm();
    if (room) {
        document.getElementById('roomNumber').value = room.room_number;
        document.getElementById('roomType').value = room.type;
        document.getElementById('roomPrice').value = room.price;
        document.getElementById('roomModalTitle').textContent = 'تعديل الغرفة';
        document.getElementById('roomSubmitText').textContent = 'حفظ التعديل';
        currentEditId = room.room_number;
    } else {
        document.getElementById('roomModalTitle').textContent = 'إضافة غرفة جديدة';
        document.getElementById('roomSubmitText').textContent = 'إضافة';
        currentEditId = null;
    }
    currentEditType = 'room';
    document.getElementById('roomModal').classList.remove('hidden');
    document.getElementById('roomModal').classList.add('flex');
}

function openAddBookingModal() {
    openBookingModal();
}

function openBookingModal(booking = null) {
    resetBookingForm();
    populateAvailableRooms(booking);
    if (booking) {
        document.getElementById('guestName').value = booking.guest_name;
        document.getElementById('guestPhone').value = booking.guest_phone;
        document.getElementById('guestIdType').value = booking.guest_id_type;
        document.getElementById('guestIdNumber').value = booking.guest_id_number;
        document.getElementById('guestNationality').value = booking.guest_nationality;
        document.getElementById('bookingRoomNumber').value = booking.room_number;
        document.getElementById('checkinDate').value = booking.checkin_date + 'T00:00';
        document.getElementById('expectedNights').value = booking.expected_nights;
        document.getElementById('bookingNotes').value = booking.notes;
        document.getElementById('bookingModalTitle').textContent = 'تعديل الحجز';
        document.getElementById('bookingSubmitText').textContent = 'حفظ التعديل';
        currentEditId = booking.booking_id;
    } else {
        document.getElementById('bookingModalTitle').textContent = 'حجز جديد';
        document.getElementById('bookingSubmitText').textContent = 'إضافة الحجز';
        currentEditId = null;
    }
    currentEditType = 'booking';
    document.getElementById('bookingModal').classList.remove('hidden');
    document.getElementById('bookingModal').classList.add('flex');
}

function openAddPaymentModal() {
    openPaymentModal();
}

function openPaymentModal(payment = null) {
    resetPaymentForm();
    populateBookingsForPayment();
    if (payment) {
        document.getElementById('paymentBookingId').value = payment.booking_id;
        document.getElementById('paymentAmount').value = payment.amount;
        document.getElementById('paymentMethod').value = payment.payment_method;
        document.getElementById('paymentDate').value = payment.payment_date + 'T00:00';
        document.getElementById('paymentNotes').value = payment.notes;
        document.getElementById('paymentModalTitle').textContent = 'تعديل الدفعة';
        document.getElementById('paymentSubmitText').textContent = 'حفظ التعديل';
        currentEditId = payment.payment_id;
    } else {
        document.getElementById('paymentModalTitle').textContent = 'إضافة دفعة جديدة';
        document.getElementById('paymentSubmitText').textContent = 'إضافة';
        currentEditId = null;
    }
    currentEditType = 'payment';
    document.getElementById('paymentModal').classList.remove('hidden');
    document.getElementById('paymentModal').classList.add('flex');
}

function openAddExpenseModal() {
    openExpenseModal();
}

function openExpenseModal(expense = null) {
    resetExpenseForm();
    if (expense) {
        document.getElementById('expenseType').value = expense.expense_type;
        document.getElementById('expenseDescription').value = expense.description;
        document.getElementById('expenseAmount').value = expense.amount;
        document.getElementById('expenseDate').value = expense.date;
        document.getElementById('expenseModalTitle').textContent = 'تعديل المصروف';
        document.getElementById('expenseSubmitText').textContent = 'حفظ التعديل';
        currentEditId = expense.id;
    } else {
        document.getElementById('expenseModalTitle').textContent = 'إضافة مصروف جديد';
        document.getElementById('expenseSubmitText').textContent = 'إضافة';
        currentEditId = null;
    }
    currentEditType = 'expense';
    document.getElementById('expenseModal').classList.remove('hidden');
    document.getElementById('expenseModal').classList.add('flex');
}

function openAddEmployeeModal() {
    openEmployeeModal();
}

function openEmployeeModal(employee = null) {
    resetEmployeeForm();
    if (employee) {
        document.getElementById('employeeName').value = employee.name;
        document.getElementById('employeeSalary').value = employee.basic_salary;
        document.getElementById('employeeStatus').value = employee.status;
        document.getElementById('employeeModalTitle').textContent = 'تعديل الموظف';
        document.getElementById('employeeSubmitText').textContent = 'حفظ التعديل';
        currentEditId = employee.id;
    } else {
        document.getElementById('employeeModalTitle').textContent = 'إضافة موظف جديد';
        document.getElementById('employeeSubmitText').textContent = 'إضافة';
        currentEditId = null;
    }
    currentEditType = 'employee';
    document.getElementById('employeeModal').classList.remove('hidden');
    document.getElementById('employeeModal').classList.add('flex');
}

function closeModal(modalId) {
    document.getElementById(modalId).classList.add('hidden');
    document.getElementById(modalId).classList.remove('flex');
}

// Reset form functions
function resetRoomForm() {
    document.getElementById('roomForm').reset();
    document.getElementById('roomId').value = '';
}

function resetBookingForm() {
    document.getElementById('bookingForm').reset();
    document.getElementById('bookingId').value = '';
    setDefaultDates();
}

function resetPaymentForm() {
    document.getElementById('paymentForm').reset();
    document.getElementById('paymentId').value = '';
    setDefaultDates();
}

function resetExpenseForm() {
    document.getElementById('expenseForm').reset();
    document.getElementById('expenseId').value = '';
    setDefaultDates();
}

function resetEmployeeForm() {
    document.getElementById('employeeForm').reset();
    document.getElementById('employeeId').value = '';
}

// Populate dropdown functions
function populateAvailableRooms(currentBooking = null) {
    const rooms = dataManager.getData('rooms');
    const roomSelect = document.getElementById('bookingRoomNumber');
    roomSelect.innerHTML = '<option value="">اختر الغرفة</option>';
    
    rooms.filter(room => 
        room.status === 'شاغرة' || 
        (currentBooking && currentBooking.room_number === room.room_number)
    ).forEach(room => {
        const option = document.createElement('option');
        option.value = room.room_number;
        option.textContent = `${room.room_number} - ${room.type} (${formatCurrency(room.price)})`;
        roomSelect.appendChild(option);
    });
}

function populateBookingsForPayment() {
    const bookings = dataManager.getData('bookings');
    const bookingSelect = document.getElementById('paymentBookingId');
    bookingSelect.innerHTML = '<option value="">اختر الحجز</option>';
    
    bookings.filter(booking => booking.status === 'محجوزة').forEach(booking => {
        const option = document.createElement('option');
        option.value = booking.booking_id;
        option.textContent = `${booking.booking_id} - ${booking.guest_name} (غرفة ${booking.room_number})`;
        bookingSelect.appendChild(option);
    });
}

// Confirmation modal
function showConfirmation(message, onConfirm) {
    document.getElementById('confirmMessage').textContent = message;
    document.getElementById('confirmModal').classList.remove('hidden');
    document.getElementById('confirmModal').classList.add('flex');
    
    document.getElementById('confirmYes').onclick = () => {
        onConfirm();
        closeModal('confirmModal');
    };
    
    document.getElementById('confirmNo').onclick = () => {
        closeModal('confirmModal');
    };
}