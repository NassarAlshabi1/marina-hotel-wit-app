// Data Management with localStorage
class DataManager {
    constructor() {
        this.storageKey = 'hotelManagementData';
        this.initializeData();
    }

    initializeData() {
        const savedData = localStorage.getItem(this.storageKey);
        if (savedData) {
            try {
                this.data = JSON.parse(savedData);
            } catch (e) {
                console.error('Error parsing saved data:', e);
                this.data = this.getDefaultData();
            }
        } else {
            this.data = this.getDefaultData();
            this.saveData();
        }
    }

    getDefaultData() {
        return {
            rooms: [
                {room_number: '101', type: 'سرير عائلي', price: 15000, status: 'محجوزة'},
                {room_number: '102', type: 'سرير عائلي', price: 15000, status: 'محجوزة'},
                {room_number: '103', type: 'سرير عائلي', price: 15000, status: 'محجوزة'},
                {room_number: '104', type: 'سرير فردي', price: 15000, status: 'محجوزة'},
                {room_number: '201', type: 'سرير فردي', price: 15000, status: 'شاغرة'},
                {room_number: '202', type: 'سرير عائلي', price: 10000, status: 'شاغرة'},
                {room_number: '203', type: 'سرير عائلي', price: 17000, status: 'شاغرة'},
                {room_number: '204', type: 'سرير فردي', price: 15000, status: 'شاغرة'},
                {room_number: '301', type: 'سرير عائلي', price: 7000, status: 'شاغرة'},
                {room_number: '302', type: 'سرير فردي', price: 15000, status: 'محجوزة'},
                {room_number: '303', type: 'سرير فردي', price: 12000, status: 'شاغرة'},
                {room_number: '304', type: 'سرير فردي', price: 10000, status: 'شاغرة'},
                {room_number: '401', type: 'سرير فردي', price: 10000, status: 'شاغرة'},
                {room_number: '402', type: 'سرير فردي', price: 10000, status: 'شاغرة'},
                {room_number: '403', type: 'سرير فردي', price: 12000, status: 'شاغرة'},
                {room_number: '404', type: 'سرير فردي', price: 14000, status: 'شاغرة'},
                {room_number: '501', type: 'سرير فردي', price: 5000, status: 'شاغرة'},
                {room_number: '502', type: 'سرير فردي', price: 7000, status: 'شاغرة'}
            ],
            bookings: [
                {booking_id: 2, guest_name: 'محمد عهد علي الموزعي', guest_phone: '22228744', room_number: '104', checkin_date: '2025-05-10', calculated_nights: 6, status: 'محجوزة', guest_id_type: 'بطاقة شخصية', guest_id_number: '1444111666', guest_nationality: 'هندي', expected_nights: 1, notes: '0'},
                {booking_id: 4, guest_name: 'نصار عبدالله حسن الشعبي', guest_phone: '773114243', room_number: '101', checkin_date: '2025-05-15', calculated_nights: 1, status: 'محجوزة', guest_id_type: 'بطاقة شخصية', guest_id_number: '5558841695', guest_nationality: 'يمني', expected_nights: 1, notes: ''},
                {booking_id: 5, guest_name: 'بلقيس فتحي سرور', guest_phone: '77311424', room_number: '102', checkin_date: '2025-05-15', calculated_nights: 1, status: 'محجوزة', guest_id_type: 'بطاقة شخصية', guest_id_number: '543322888', guest_nationality: 'يمني', expected_nights: 1, notes: 'تريد تطول'},
                {booking_id: 8, guest_name: 'فايز صالح عبدالله ابوجهلان', guest_phone: '967774399835', room_number: '302', checkin_date: '2025-06-19', calculated_nights: 8, status: 'محجوزة', guest_id_type: 'بطاقة شخصية', guest_id_number: '11010257418', guest_nationality: 'يمني', expected_nights: 1, notes: ''},
                {booking_id: 9, guest_name: 'محمد احمد علي عماد', guest_phone: '967783769730', room_number: '103', checkin_date: '2025-06-29', calculated_nights: 1, status: 'محجوزة', guest_id_type: 'بطاقة شخصية', guest_id_number: '54545545', guest_nationality: 'يمني', expected_nights: 1, notes: ''}
            ],
            payments: [
                {payment_id: 13, booking_id: 4, amount: 15000, payment_date: '2025-05-16', payment_method: 'نقدي', notes: ''},
                {payment_id: 12, booking_id: 5, amount: 10000, payment_date: '2025-05-10', payment_method: 'نقدي', notes: ''},
                {payment_id: 11, booking_id: 2, amount: 90000, payment_date: '2025-05-15', payment_method: 'نقدي', notes: ''},
                {payment_id: 15, booking_id: 8, amount: 88000, payment_date: '2025-06-26', payment_method: 'نقدي', notes: ''},
                {payment_id: 23, booking_id: 9, amount: 10000, payment_date: '2025-06-28', payment_method: 'نقدي', notes: ''}
            ],
            expenses: [
                {id: 1, expense_type: 'utilities', description: 'فاتورة كهرباء', amount: 450000, date: '2025-05-10'},
                {id: 2, expense_type: 'other', description: 'ديزل', amount: 21500, date: '2025-05-23'},
                {id: 3, expense_type: 'other', description: 'ديزل', amount: 20000, date: '2025-05-24'},
                {id: 4, expense_type: 'purchases', description: 'ديزل 11', amount: 25000, date: '2025-05-24'},
                {id: 5, expense_type: 'purchases', description: 'قصبة', amount: 2000, date: '2025-05-24'}
            ],
            employees: [
                {id: 1, name: 'محمد احمد', basic_salary: 150000, status: 'active'},
                {id: 2, name: 'عبدالله طه', basic_salary: 120000, status: 'active'},
                {id: 3, name: 'عمار الشوب', basic_salary: 100000, status: 'active'},
                {id: 4, name: 'سعيد الاورمو', basic_salary: 110000, status: 'active'}
            ],
            settings: {
                hotelName: 'فندق النجمة الذهبية',
                hotelAddress: 'عدن، اليمن',
                hotelPhone: '+967 123 456 789',
                password: '1234'
            }
        };
    }

    saveData() {
        try {
            localStorage.setItem(this.storageKey, JSON.stringify(this.data));
            return true;
        } catch (e) {
            console.error('Error saving data:', e);
            return false;
        }
    }

    getData(type) {
        return this.data[type] || [];
    }

    addItem(type, item) {
        if (!this.data[type]) {
            this.data[type] = [];
        }
        this.data[type].push(item);
        this.saveData();
    }

    updateItem(type, id, updatedItem) {
        const items = this.data[type];
        const index = items.findIndex(item => {
            if (type === 'rooms') return item.room_number === id;
            if (type === 'bookings') return item.booking_id === id;
            if (type === 'payments') return item.payment_id === id;
            if (type === 'expenses') return item.id === id;
            if (type === 'employees') return item.id === id;
            return false;
        });
        
        if (index !== -1) {
            items[index] = updatedItem;
            this.saveData();
            return true;
        }
        return false;
    }

    deleteItem(type, id) {
        const items = this.data[type];
        const index = items.findIndex(item => {
            if (type === 'rooms') return item.room_number === id;
            if (type === 'bookings') return item.booking_id === id;
            if (type === 'payments') return item.payment_id === id;
            if (type === 'expenses') return item.id === id;
            if (type === 'employees') return item.id === id;
            return false;
        });
        
        if (index !== -1) {
            items.splice(index, 1);
            this.saveData();
            return true;
        }
        return false;
    }

    exportData() {
        return JSON.stringify(this.data, null, 2);
    }

    importData(jsonData) {
        try {
            const importedData = JSON.parse(jsonData);
            this.data = importedData;
            this.saveData();
            return true;
        } catch (e) {
            console.error('Error importing data:', e);
            return false;
        }
    }

    resetData() {
        this.data = this.getDefaultData();
        this.saveData();
    }
}