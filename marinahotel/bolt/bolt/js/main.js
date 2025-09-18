// Main application initialization
let dataManager;

// Initialize the application
document.addEventListener('DOMContentLoaded', function() {
    // Initialize data manager
    dataManager = new DataManager();
    
    // Initialize components
    initializeAuth();
    initializeNavigation();
    initializeModals();
    
    // Set up file input for import
    document.getElementById('fileInput').addEventListener('change', function(e) {
        const file = e.target.files[0];
        if (file) {
            const reader = new FileReader();
            reader.onload = function(e) {
                try {
                    const success = dataManager.importData(e.target.result);
                    if (success) {
                        // Reload current section
                        const currentSection = document.querySelector('[id$="Section"]:not(.hidden)');
                        if (currentSection) {
                            const sectionName = currentSection.id.replace('Section', '');
                            loadSectionContent(sectionName);
                        }
                        showNotification('تم استيراد البيانات بنجاح');
                    } else {
                        showNotification('خطأ في استيراد البيانات', 'error');
                    }
                } catch (error) {
                    showNotification('ملف غير صالح', 'error');
                }
            };
            reader.readAsText(file);
        }
    });
    
    // Close modals when clicking outside
    window.addEventListener('click', function(e) {
        if (e.target.classList.contains('modal')) {
            e.target.classList.add('hidden');
            e.target.classList.remove('flex');
        }
    });
    
    // Update date and time
    updateDateTime();
    setInterval(updateDateTime, 1000);
    
    // Set default dates
    setDefaultDates();
});