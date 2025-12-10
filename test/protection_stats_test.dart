import 'package:digital_defender/logic/protection_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses valid json with defaults', () {
    final stats = ProtectionStats.fromJson({
      'blockedCount': 10,
      'sessionBlocked': 3,
      'running': true,
      'mode': 'ultra',
      'failOpenActive': true,
      'recent': [
        {'domain': 'example.com', 'timestamp': 1000},
      ],
    });

    expect(stats.blockedCount, 10);
    expect(stats.sessionBlocked, 3);
    expect(stats.isRunning, isTrue);
    expect(stats.mode, ProtectionMode.ultra);
    expect(stats.failOpenActive, isTrue);
    expect(stats.recent.single.domain, 'example.com');
  });

  test('handles missing fields gracefully', () {
    final stats = ProtectionStats.fromJson({});

    expect(stats.blockedCount, 0);
    expect(stats.sessionBlocked, 0);
    expect(stats.isRunning, isFalse);
    expect(stats.mode, ProtectionMode.standard);
    expect(stats.recent, isEmpty);
  });
}
