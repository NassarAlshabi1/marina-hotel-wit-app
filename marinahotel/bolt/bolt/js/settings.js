// Settings management functions
function loadSettingsSection() {
    const settingsSection = document.getElementById('settingsSection');
    const settings = dataManager.data.settings;
    
    settingsSection.innerHTML = `
        <h2 class="text-2xl font-bold text-gray-800 mb-6">الإعدادات</h2>
        
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <div class="bg-white p-6 rounded-xl shadow-sm">
                <h3 class="text-lg font-semibold text-gray-800 mb-4">إعدادات النظام</h3>
                <form id="systemSettingsForm" class="space-y-4">
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">اسم الفندق</label>
                        <input type="text" id="hotelName" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" value="${settings.hotelName}">
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">العنوان</label>
                        <textarea id="hotelAddress" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" rows="3">${settings.hotelAddress}</textarea>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">رقم الهاتف</label>
                        <input type="text" id="hotelPhone" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500" value="${settings.hotelPhone}">
                    </div>
                    <button type="submit" class="w-full bg-blue-600 text-white py-2 rounded-lg hover:bg-blue-700 transition-colors">
                        حفظ الإعدادات
                    </button>
                </form>
            </div>
            
            <div class="bg-white p-6 rounded-xl shadow-sm">
                <h3 class="text-lg font-semibold text-gray-800 mb-4">إدارة البيانات</h3>
                <div class="space-y-4">
                    <button onclick="backupData()" class="w-full bg-green-600 text-white py-2 rounded-lg hover:bg-green-700 transition-colors">
                        <i class="fas fa-download ml-2"></i>
                        نسخ احتياطي للبيانات
                    </button>
                    <button onclick="restoreData()" class="w-full bg-blue-600 text-white py-2 rounded-lg hover:bg-blue-700 transition-colors">
                        <i class="fas fa-upload ml-2"></i>
                        استعادة البيانات
                    </button>
                    <button onclick="resetData()" class="w-full bg-red-600 text-white py-2 rounded-lg hover:bg-red-700 transition-colors">
                        <i class="fas fa-trash ml-2"></i>
                        إعادة تعيين البيانات
                    </button>
                </div>
                
                <div class="mt-6">
                    <h4 class="text-md font-semibold text-gray-800 mb-2">تغيير كلمة المرور</h4>
                    <form id="passwordChangeForm" class="space-y-3">
                        <input type="password" id="currentPassword" placeholder="كلمة المرور الحالية" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500">
                        <input type="password" id="newPassword" placeholder="كلمة المرور الجديدة" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500">
                        <input type="password" id="confirmPassword" placeholder="تأكيد كلمة المرور" class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500">
                        <button type="submit" class="w-full bg-purple-600 text-white py-2 rounded-lg hover:bg-purple-700 transition-colors">
                            تغيير كلمة المرور
                        </button>
                    </form>
                </div>
            </div>
        </div>
    `;
    
    initializeSettingsForms();
}

function initializeSettingsForms() {
    // System settings form
    document.getElementById('systemSettingsForm').addEventListener('submit', function(e) {
        e.preventDefault();
        dataManager.data.settings.hotelName = document.getElementById('hotelName').value;
        dataManager.data.settings.hotelAddress = document.getElementById('hotelAddress').value;
        dataManager.data.settings.hotelPhone = document.getElementById('hotelPhone').value;
        dataManager.saveData();
        showNotification('تم حفظ إعدادات النظام بنجاح');
    });

    // Password change form
    document.getElementById('passwordChangeForm').addEventListener('submit', function(e) {
        e.preventDefault();
        const currentPassword = document.getElementById('currentPassword').value;
        const newPassword = document.getElementById('newPassword').value;
        const confirmPassword = document.getElementById('confirmPassword').value;
        
        if (currentPassword !== dataManager.data.settings.password) {
            showNotification('كلمة المرور الحالية غير صحيحة', 'error');
            return;
        }
        
        if (newPassword !== confirmPassword) {
            showNotification('كلمة المرور الجديدة غير متطابقة', 'error');
            return;
        }
        
        if (newPassword.length < 4) {
            showNotification('كلمة المرور يجب أن تكون 4 أحرف على الأقل', 'error');
            return;
        }
        
        dataManager.data.settings.password = newPassword;
        dataManager.saveData();
        showNotification('تم تغيير كلمة المرور بنجاح');
        document.getElementById('passwordChangeForm').reset();
    });
}

function backupData() {
    exportData();
}

function restoreData() {
    importData();
}

function resetData() {
    showConfirmation('هل أنت متأكد من إعادة تعيين جميع البيانات؟ سيتم فقدان جميع البيانات الحالية!', () => {
        dataManager.resetData();
        // Reload current section
        const currentSection = document.querySelector('[id$="Section"]:not(.hidden)');
        if (currentSection) {
            const sectionName = currentSection.id.replace('Section', '');
            loadSectionContent(sectionName);
        }
        showNotification('تم إعادة تعيين البيانات بنجاح');
    });
}