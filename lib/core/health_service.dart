import 'dart:math';

import 'models.dart';
import 'health_impl_stub.dart' if (dart.library.io) 'health_impl_native.dart' as impl;

/// Steps source. Native builds read HealthKit / Health Connect through the
/// `health` plugin; web and desktop fall back to a deterministic demo source
/// so the whole app is demoable in a browser.
abstract class StepsSource {
  bool get isReal;
  Future<bool> connect();
  Future<List<StepDay>> lastDays(int days);
}

StepsSource createStepsSource() => impl.createStepsSource();

class DemoStepsSource implements StepsSource {
  @override
  bool get isReal => false;

  @override
  Future<bool> connect() async => true;

  @override
  Future<List<StepDay>> lastDays(int days) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rnd = Random(42);
    final out = <StepDay>[];
    for (var i = days - 1; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final base = d.weekday >= 6 ? 11000 : 7000;
      final steps = i == 0
          ? (base * 0.62).round() + rnd.nextInt(600)
          : base + rnd.nextInt(4000) - 1500;
      out.add(StepDay(d, max(0, steps)));
    }
    return out;
  }
}
