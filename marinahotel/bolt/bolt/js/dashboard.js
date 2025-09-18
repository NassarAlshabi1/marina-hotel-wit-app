// Dashboard functions
function loadDashboard() {
    updateStats();
    loadRecentBookings();
    initializeCharts();
}

function updateStats() {
    const rooms = dataManager.getData('rooms');
    const payments = dataManager.getData('payments');
    
    const totalRooms = rooms.length;
    const occupiedRooms = rooms.filter(room => room.status === 'محجوزة').length;
    const availableRooms = totalRooms - occupiedRooms;
    const monthlyRevenue = payments.reduce((sum, payment) => sum + payment.amount, 0);
    
    document.getElementById('totalRooms').textContent = totalRooms;
    document.getElementById('occupiedRooms').textContent = occupiedRooms;
    document.getElementById('availableRooms').textContent = availableRooms;
    document.getElementById('monthlyRevenue').textContent = monthlyRevenue.toLocaleString();
}

function loadRecentBookings() {
    const bookings = dataManager.getData('bookings');
    const recentBookingsTable = document.getElementById('recentBookingsTable');
    recentBookingsTable.innerHTML = '';
    
    bookings.slice(0, 5).forEach(booking => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${booking.guest_name}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${booking.room_number}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${booking.checkin_date}</td>
            <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">${booking.calculated_nights}</td>
            <td class="px-6 py-4 whitespace-nowrap">
                <span class="px-2 py-1 text-xs rounded-full ${booking.status === 'محجوزة' ? 'status-occupied' : 'status-available'}">
                    ${booking.status}
                </span>
            </td>
        `;
        recentBookingsTable.appendChild(row);
    });
}

function initializeCharts() {
    // Revenue Chart
    const revenueCtx = document.getElementById('revenueChart');
    if (revenueCtx) {
        new Chart(revenueCtx.getContext('2d'), {
            type: 'line',
            data: {
                labels: ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو'],
                datasets: [{
                    label: 'الإيرادات (ريال يمني)',
                    data: [1200000, 1900000, 3000000, 5000000, 2300000, 3200000],
                    borderColor: 'rgb(59, 130, 246)',
                    backgroundColor: 'rgba(59, 130, 246, 0.1)',
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
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

    // Occupancy Chart
    const occupancyCtx = document.getElementById('occupancyChart');
    if (occupancyCtx) {
        const rooms = dataManager.getData('rooms');
        const occupiedCount = rooms.filter(room => room.status === 'محجوزة').length;
        const availableCount = rooms.length - occupiedCount;
        
        new Chart(occupancyCtx.getContext('2d'), {
            type: 'doughnut',
            data: {
                labels: ['محجوزة', 'شاغرة'],
                datasets: [{
                    data: [occupiedCount, availableCount],
                    backgroundColor: ['#dc2626', '#16a34a'],
                    borderWidth: 0
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'bottom'
                    }
                }
            }
        });
    }
}