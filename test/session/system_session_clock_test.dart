import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/session/live_session_controller.dart';

void main() {
  group('SystemSessionClock', () {
    test('ticks emits pulses without throwing', () async {
      // Regression test (smoke test 6.1): Stream.periodic without a
      // computation callback throws at runtime when the event type is
      // non-nullable (Dart 3.13). The controller tests inject a fake
      // clock, so the production clock needs its own coverage.
      const clock = SystemSessionClock(
        tickInterval: Duration(milliseconds: 5),
      );
      final received = <int>[];
      final sub = clock.ticks().listen(received.add);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await sub.cancel();
      expect(received, isNotEmpty);
    });

    test('now returns the wall clock', () {
      final before = DateTime.now();
      final now = SystemSessionClock().now();
      final after = DateTime.now();
      expect(now.isBefore(before), isFalse);
      expect(now.isAfter(after), isFalse);
    });
  });
}
