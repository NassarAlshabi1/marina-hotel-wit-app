import 'dart:async';
import 'package:flutter/foundation.dart';
import 'local_db.dart';
import 'database_health_checker.dart';

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
      if (!DatabaseManager.isInitialized) {
        throw StateError('Database is not initialized. Cannot perform $opName');
      }
      
      final isHealthy = await _healthChecker.ensureHealthy(timeout: const Duration(seconds: 3));
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
      debugPrint('❌ StateError in $opName: $e');
      debugPrint(stack.toString());
      
      if (throwOnError) {
        rethrow;
      } else if (fallbackValue != null) {
        return fallbackValue;
      } else {
        rethrow;
      }
    } catch (e, stack) {
      debugPrint('❌ Error in $opName: $e');
      debugPrint(stack.toString());
      
      if (e.toString().contains('connection was closed') || 
          e.toString().contains('isolate channel')) {
        debugPrint('⚠️ Database connection error detected. This may require app restart.');
        
        try {
          await DatabaseManager.reopen();
          debugPrint('✅ Database reopened successfully. Retrying operation...');
          
          final db = DatabaseManager.instance;
          return await operation(db).timeout(timeout);
        } catch (retryError) {
          debugPrint('❌ Retry failed: $retryError');
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
        if (isClosed) return;
        
        try {
          if (!DatabaseManager.isInitialized) {
            controller.addError(StateError('Database not initialized for $opName'));
            controller.close();
            return;
          }
          
          final db = DatabaseManager.instance;
          final stream = streamFactory(db);
          
          subscription = stream.listen(
            (data) {
              if (!isClosed) {
                controller.add(data);
              }
            },
            onError: (error, stackTrace) {
              if (error.toString().contains('connection was closed') ||
                  error.toString().contains('isolate channel')) {
                debugPrint('⚠️ Database stream error: $error. Attempting to recover...');
                
                subscription?.cancel();
                
                Future.delayed(const Duration(milliseconds: 500), () async {
                  try {
                    await DatabaseManager.reopen();
                    debugPrint('✅ Database reopened. Recreating stream...');
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
    return await _healthChecker.ensureHealthy();
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
