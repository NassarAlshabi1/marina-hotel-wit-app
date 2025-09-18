// Rooms management functions
function loadRoomsSection() {
    const roomsSection = document.getElementById('roomsSection');
    roomsSection.innerHTML = `
        <div class="flex justify-between items-center mb-6">
            <h2 class="text-2xl font-bold text-gray-800">إدارة الغرف</h2>
            <button onclick="openAddRoomModal()" class="btn-primary text-white px-6 py-2 rounded-lg">
                <i class="fas fa-plus ml-2"></i>
                إضافة غرفة جديدة
            </button>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6 gap-4" id="roomsGrid">
            <!-- Rooms will be populated here -->
        </div>
    `;
    
    loadRooms();
}

function loadRooms() {
    const rooms = dataManager.getData('rooms');
    const roomsGrid = document.getElementById('roomsGrid');
    if (!roomsGrid) return;
    
    roomsGrid.innerHTML = '';
    
    rooms.forEach(room => {
        const roomCard = document.createElement('div');
        roomCard.className = `room-card p-4 rounded-lg cursor-pointer ${room.status === 'محجوزة' ? 'occupied' : 'available'}`;
        roomCard.innerHTML = `
            <div class="text-center">
                <div class="text-2xl font-bold text-gray-800 mb-2">${room.room_number}</div>
                <div class="text-sm text-gray-600 mb-2">${room.type}</div>
                <div class="text-lg font-semibold text-blue-600 mb-2">${formatCurrency(room.price)}</div>
                <div class="text-xs px-2 py-1 rounded-full mb-2 ${room.status === 'محجوزة' ? 'status-occupied' : 'status-available'}">
                    ${room.status}
                </div>
                <div class="flex justify-center space-x-2 space-x-reverse">
                    <button onclick="editRoom('${room.room_number}')" class="text-blue-600 hover:text-blue-800 p-1">
                        <i class="fas fa-edit"></i>
                    </button>
                    <button onclick="deleteRoom('${room.room_number}')" class="text-red-600 hover:text-red-800 p-1">
                        <i class="fas fa-trash"></i>
                    </button>
                </div>
            </div>
        `;
        roomsGrid.appendChild(roomCard);
    });
}

function editRoom(roomNumber) {
    const rooms = dataManager.getData('rooms');
    const room = rooms.find(r => r.room_number === roomNumber);
    if (room) {
        openRoomModal(room);
    }
}

function deleteRoom(roomNumber) {
    const rooms = dataManager.getData('rooms');
    const room = rooms.find(r => r.room_number === roomNumber);
    if (room && room.status === 'محجوزة') {
        showNotification('لا يمكن حذف غرفة محجوزة', 'error');
        return;
    }
    
    showConfirmation('هل أنت متأكد من حذف هذه الغرفة؟', () => {
        if (dataManager.deleteItem('rooms', roomNumber)) {
            loadRooms();
            updateStats();
            showNotification('تم حذف الغرفة بنجاح');
        }
    });
}