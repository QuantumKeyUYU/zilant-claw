import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class TestBlocklist {
  TestBlocklist({required this.blockedExact, required this.blockedWildcard, required this.allowExact, required this.allowWildcard});

  final Set<String> blockedExact;
  final Set<String> blockedWildcard;
  final Set<String> allowExact;
  final Set<String> allowWildcard;

  factory TestBlocklist.fromLines(List<String> lines) {
    final blockedExact = <String>{};
    final blockedWildcard = <String>{};
    final allowExact = <String>{};
    final allowWildcard = <String>{};

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final isAllow = line.startsWith('@@');
      final content = isAllow ? line.substring(2) : line;
      if (content.startsWith('*.')) {
        final domain = content.substring(2).toLowerCase();
        if (domain.isNotEmpty) {
          (isAllow ? allowWildcard : blockedWildcard).add(domain);
        }
      } else {
        final domain = content.toLowerCase();
        if (domain.isNotEmpty) {
          (isAllow ? allowExact : blockedExact).add(domain);
        }
      }
    }

    return TestBlocklist(
      blockedExact: blockedExact,
      blockedWildcard: blockedWildcard,
      allowExact: allowExact,
      allowWildcard: allowWildcard,
    );
  }

  bool isBlocked(String domain) {
    final normalized = domain.toLowerCase();
    if (_matches(normalized, allowExact, allowWildcard)) {
      return false;
    }
    return _matches(normalized, blockedExact, blockedWildcard);
  }

  bool _matches(String domain, Set<String> exact, Set<String> wildcard) {
    if (exact.contains(domain)) return true;
    for (final rule in wildcard) {
      if (domain == rule || domain.endsWith('.$rule')) {
        return true;
      }
    }
    return false;
  }
}

void main() {
  test('domains from blocklists are blocked while allowlist wins', () {
    final standardLines = File('assets/blocklists/blocklist_standard.txt').readAsLinesSync();
    final ultraLines = File('android/app/src/main/assets/blocklists/blocklist_ultra_extra.txt').readAsLinesSync();

    final lines = [
      ...standardLines,
      ...ultraLines,
      '*.telemetry.example',
      '@@allowed.telemetry.example',
    ];

    final blocklist = TestBlocklist.fromLines(lines);

    expect(blocklist.isBlocked('google-analytics.com'), isTrue);
    expect(blocklist.isBlocked('ads-api.tiktok.com'), isTrue);
    expect(blocklist.isBlocked('sub.telemetry.example'), isTrue);
    expect(blocklist.isBlocked('allowed.telemetry.example'), isFalse);
  });
}
