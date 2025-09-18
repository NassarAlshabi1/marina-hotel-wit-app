// Authentication functions
function initializeAuth() {
    document.getElementById('loginForm').addEventListener('submit', function(e) {
        e.preventDefault();
        const username = document.getElementById('username').value;
        const password = document.getElementById('password').value;
        
        if (username === 'admin' && password === dataManager.data.settings.password) {
            document.getElementById('loginScreen').classList.add('hidden');
            document.getElementById('mainApp').classList.remove('hidden');
            showSection('dashboard');
            showNotification('تم تسجيل الدخول بنجاح');
        } else {
            showNotification('اسم المستخدم أو كلمة المرور غير صحيحة', 'error');
        }
    });
}

function logout() {
    document.getElementById('loginScreen').classList.remove('hidden');
    document.getElementById('mainApp').classList.add('hidden');
    document.getElementById('username').value = '';
    document.getElementById('password').value = '';
    showNotification('تم تسجيل الخروج بنجاح');
}