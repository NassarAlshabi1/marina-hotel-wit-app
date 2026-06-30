// ignore_for_file: unused_field, unused_element
import '../adapters/adapter_registry.dart';
import '../appwrite_error_handler.dart';
import '../appwrite_logger.dart';
import '../appwrite_service.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/rooms_repository.dart';
import 'sync_error_service.dart';

/// خدمة دفع التغييرات المحلية إلى Appwrite Cloud
///
/// نسخة مُنظَّفة (v2) — جميع الدوال الـ17 المكررة (_pushAllEntities, _processXxxEntry,
/// _xxxToRemote) محذوفة لأنها مُكررة في AppwriteSyncManager ولا تُستدعى عبر
/// `_pushService.` إطلاقًا.
///
/// هذا الصنف يُحتفظ به فقط للتوافق مع `sync_providers.dart` و `AppwriteSyncManager`
/// اللذين يُنشئانه كـ field. إذا أردت استخدامه فعليًا، انقل دوال الدفع من
/// `AppwriteSyncManager` إلى هنا.
class SyncPushService {
  SyncPushService({
    required this.appwriteService,
    required this.database,
    required this.outboxDao,
    AdapterRegistry? adapterRegistry,
    BookingsRepository? bookingsRepository,
    RoomsRepository? roomsRepository,
    SyncErrorService? errorService,
    AppwriteLogger? logger,
    AppwriteErrorHandler? errorHandler,
  })  : _adapterRegistry = adapterRegistry ?? AdapterRegistry(database),
        _bookingsRepository = bookingsRepository ?? BookingsRepository(database),
        _roomsRepository = roomsRepository ?? RoomsRepository(database),
        _err = errorService ?? SyncErrorService(tag: 'PUSH'),
        _logger = logger ?? AppwriteLogger(),
        _errorHandler = errorHandler ?? AppwriteErrorHandler();

  final AppwriteService appwriteService;
  final AppDatabase database;
  final OutboxDao outboxDao;
  final AdapterRegistry _adapterRegistry;
  final BookingsRepository _bookingsRepository;
  final RoomsRepository _roomsRepository;
  final AppwriteLogger _logger;
  final AppwriteErrorHandler _errorHandler;
  final SyncErrorService _err;

  // TODO: انقل دوال الدفع (_pushAllEntities, _processXxxEntry) من AppwriteSyncManager
  //       إلى هنا عند تفكيك الـ God Class في المرحلة 3.
}
