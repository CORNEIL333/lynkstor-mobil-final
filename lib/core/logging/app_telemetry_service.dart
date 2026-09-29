import 'dart:async';

import '../../shared/services/analytics_service.dart';
import '../logging/app_logger.dart';
import '../utils/id_generator.dart';

class TelemetryEvent {
  const TelemetryEvent({
    required this.id,
    required this.message,
    required this.severity,
    required this.timestamp,
    this.stackTrace,
  });

  final String id;
  final String message;
  final String severity;
  final DateTime timestamp;
  final String? stackTrace;

  Map<String, dynamic> toJson() => {
    'id': id,
    'message': message,
    'severity': severity,
    'timestamp': timestamp.toIso8601String(),
    'stackTrace': stackTrace,
  };
}

/// Service de télémétrie et journalisation des erreurs hors-ligne.
class AppTelemetryService {
  AppTelemetryService._();

  static final List<TelemetryEvent> _eventQueue = [];

  static void captureException(
    dynamic error, [
    StackTrace? stackTrace,
    String severity = 'error',
  ]) {
    final event = TelemetryEvent(
      id: IdGenerator.uuid(),
      message: error.toString(),
      severity: severity,
      timestamp: DateTime.now(),
      stackTrace: stackTrace?.toString(),
    );

    _eventQueue.add(event);
    AppAnalytics.track('error.captured', properties: {'severity': severity});
    AppLogger.e(
      'Telemetry captured error: ${event.message}',
      error,
      stackTrace,
    );
  }

  static Future<void> flushQueue({String? endpointUrl}) async {
    if (_eventQueue.isEmpty) return;

    AppLogger.i(
      'Telemetry: flushing ${_eventQueue.length} pending error events',
    );
    _eventQueue.clear();
  }

  static int get pendingCount => _eventQueue.length;
}
