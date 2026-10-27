/// ملف Providers المركزي لخدمات التطبيق
/// يعيد تصدير المزودات الأساسية للاستخدام في أجزاء التطبيق المختلفة
library;

export '../providers/repository_providers.dart'
    show
        databaseProvider,
        roomsRepoProvider,
        bookingsRepoProvider,
        paymentsRepoProvider,
        debtsRepoProvider,
        whatsappServiceProvider;
