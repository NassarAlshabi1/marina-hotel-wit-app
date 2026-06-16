import 'dart:async';

import 'package:flutter/foundation.dart';

import 'database_health_checker.dart';
import 'local_db.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

class SafeDatabaseOperations {
  static final _healthChecker = DatabaseHealthChecker.instance;

  static Future<T> execute<T>({
    required Future<T> Function(AppDatabase db) operation,
    String? operationName,
    T? fallbackValue,
    bool throwOnError = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final opName = operationName ?? 'database_operation';

    try {
      // التحقق من حالة الاستعادة
      if (DatabaseManager.isRestoring) {
        AppLogger.info('⏸️ Operation $opName paused: database is being restored', tag: 'APP');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (DatabaseManager.isRestoring) {
          throw StateError(
            'Database is being restored. Please try again later.',
          );
        }
      }

      if (!DatabaseManager.isInitialized) {
        throw StateError('Database is not initialized. Cannot perform $opName');
      }

      final isHealthy = await _healthChecker.ensureHealthy(
        timeout: const Duration(seconds: 3),
      );
      if (!isHealthy) {
        throw StateError('Database health check failed for $opName');
      }

      final db = DatabaseManager.instance;

      final result = await operation(db).timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException('Database operation timed out: $opName');
        },
      );

      return result;
    } on StateError catch (e, stack) {
      AppLogger.error('❌ StateError in $opName: $e', tag: 'APP');
      AppLogger.info(
  stack.toString(),
  tag: 'APP',
);

      if (throwOnError) {
        rethrow;
      } else if (fallbackValue != null) {
        return fallbackValue;
      } else {
        rethrow;
      }
    } catch (e, stack) {
      AppLogger.error('❌ Error in $opName: $e', tag: 'APP');
      AppLogger.info(
  stack.toString(),
  tag: 'APP',
);

      // معالجة أخطاء قاعدة البيانات الشائعة
      final errorStr = e.toString();
      if (errorStr.contains('connection was closed') ||
          errorStr.contains('isolate channel') ||
          errorStr.contains('Can\'t re-open a database') ||
          errorStr.contains('DatabaseManager has been closed')) {
        AppLogger.warning('⚠️ Database connection error detected in $opName', tag: 'APP');

        // عدم محاولة reopen إذا كانت استعادة جارية
        if (DatabaseManager.isRestoring) {
          AppLogger.info('⏸️ Database is being restored, will not attempt reopen', tag: 'APP');
          throw StateError('Database is being restored');
        }

        try {
          AppLogger.info('🔄 Attempting to reopen database...', tag: 'APP');
          await DatabaseManager.reopen();
          AppLogger.info('✅ Database reopened successfully. Retrying operation...', tag: 'APP');

          final db = DatabaseManager.instance;
          return await operation(db).timeout(timeout);
        } catch (retryError) {
          AppLogger.error('❌ Retry failed: $retryError', tag: 'APP');
          if (throwOnError) {
            rethrow;
          } else if (fallbackValue != null) {
            return fallbackValue;
          } else {
            rethrow;
          }
        }
      }

      if (throwOnError) {
        rethrow;
      } else if (fallbackValue != null) {
        return fallbackValue;
      } else {
        rethrow;
      }
    }
  }

  static Stream<T> executeStream<T>({
    required Stream<T> Function(AppDatabase db) streamFactory,
    String? operationName,
  }) {
    final opName = operationName ?? 'database_stream';

    return Stream.multi((controller) {
      StreamSubscription<T>? subscription;
      bool isClosed = false;

      void setupStream() {
        if (isClosed) {
          return;
        }

        try {
          // التحقق من حالة الاستعادة
          if (DatabaseManager.isRestoring) {
            AppLogger.info('⏸️ Stream $opName paused: database is being restored', tag: 'APP');
            Future<void>.delayed(const Duration(milliseconds: 200), () {
              if (!isClosed && !DatabaseManager.isRestoring) {
                setupStream();
              }
            });
            return;
          }

          if (!DatabaseManager.isInitialized) {
            AppLogger.warning(
  '⚠️ Database not initialized for $opName. Attempting to initialize...',
  tag: 'APP',
);
            try {
              // محاولة الحصول على instance لتهيئة قاعدة البيانات
              final _ = DatabaseManager.instance;
            } catch (e) {
              controller.addError(
                StateError('Failed to initialize database for $opName: $e'),
              );
              controller.close();
              return;
            }
          }

          final db = DatabaseManager.instance;
          final stream = streamFactory(db);

          subscription = stream.listen(
            (data) {
              if (!isClosed) {
                controller.add(data);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              final errorStr = error.toString();
              if (errorStr.contains('connection was closed') ||
                  errorStr.contains('isolate channel') ||
                  errorStr.contains('Can\'t re-open a database') ||
                  errorStr.contains('DatabaseManager has been closed')) {
                AppLogger.warning(
  '⚠️ Database stream error: $error. Attempting to recover...',
  tag: 'APP',
);

                subscription?.cancel();

                // التحقق من حالة الاستعادة قبل المحاولة
                if (DatabaseManager.isRestoring) {
                  AppLogger.info(
  '⏸️ Database is being restored, will retry after restore completes',
  tag: 'APP',
);
                  Future<void>.delayed(const Duration(seconds: 1), () {
                    if (!isClosed && !DatabaseManager.isRestoring) {
                      setupStream();
                    }
                  });
                  return;
                }

                Future<void>.delayed(const Duration(milliseconds: 500), () async {
                  try {
                    AppLogger.info(
  '🔄 Attempting to reopen database for stream...',
  tag: 'APP',
);
                    await DatabaseManager.reopen();
                    AppLogger.info('✅ Database reopened. Recreating stream...', tag: 'APP');
                    setupStream();
                  } catch (e) {
                    if (!isClosed) {
                      controller.addError(e, stackTrace);
                    }
                  }
                });
              } else {
                if (!isClosed) {
                  controller.addError(error, stackTrace);
                }
              }
            },
            onDone: () {
              if (!isClosed) {
                controller.close();
              }
            },
          );
        } catch (e, stack) {
          if (!isClosed) {
            controller.addError(e, stack);
            controller.close();
          }
        }
      }

      setupStream();

      controller.onCancel = () {
        isClosed = true;
        subscription?.cancel();
      };
    });
  }

  static Future<bool> isConnectionHealthy() async {
    return _healthChecker.ensureHealthy();
  }

  static Stream<DatabaseHealth> watchHealth() {
    return _healthChecker.healthStream;
  }

  static void startHealthMonitoring() {
    _healthChecker.startMonitoring();
  }

  static void stopHealthMonitoring() {
    _healthChecker.stopMonitoring();
  }
}
