import 'package:flutter/foundation.dart';

/// Fire-and-forget deep-link bus. Notification taps and background payloads
/// land here; the shell/today screen subscribe and route themselves.
///
/// Supported links:
///   'task' payload  → open the TASKS tab (task id kept for future highlight)
///   'shared_queue'  → open the TODAY tab and pop the SHARED queue dialog
class DeepLinks {
  DeepLinks._();

  /// Non-null while a SHARED-queue open has been requested.
  static final ValueNotifier<int> sharedQueueRequests = ValueNotifier<int>(0);

  /// Non-null while a TASKS-tab open has been requested (payload task id kept
  /// for future highlight support; currently just switches tabs).
  static final ValueNotifier<int> tasksRequests = ValueNotifier<int>(0);

  static void handle(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (payload == 'shared_queue') sharedQueueRequests.value++;
    if (payload.startsWith('task')) tasksRequests.value++;
  }
}
