import 'dart:io';

import 'package:health/health.dart';

import 'health_service.dart';
import 'models.dart';

StepsSource createStepsSource() =>
    (Platform.isIOS || Platform.isAndroid) ? HealthStepsSource() : DemoStepsSource();

/// Apple Health (HealthKit) on iOS and Health Connect on Android via the
/// `health` plugin. Read-only: we only ask for STEPS.
class HealthStepsSource implements StepsSource {
  final Health _health = Health();
  bool _configured = false;
  bool _authorized = false;

  @override
  bool get isReal => true;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> connect() async {
    await _ensureConfigured();
    const types = [HealthDataType.STEPS];
    const perms = [HealthDataAccess.READ];
    final has = await _health.hasPermissions(types, permissions: perms);
    if (has == true) {
      _authorized = true;
      return true;
    }
    _authorized = await _health.requestAuthorization(types, permissions: perms);
    return _authorized;
  }

  @override
  Future<List<StepDay>> lastDays(int days) async {
    if (!_authorized && !await connect()) {
      throw StateError('Health permission not granted');
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <StepDay>[];
    for (var i = days - 1; i >= 0; i--) {
      final start = today.subtract(Duration(days: i));
      final end = i == 0 ? now : start.add(const Duration(days: 1));
      final steps = await _health.getTotalStepsInInterval(start, end) ?? 0;
      out.add(StepDay(start, steps));
    }
    return out;
  }
}
