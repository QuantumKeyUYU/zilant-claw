import 'dart:async';
import 'dart:convert';

import 'package:digital_defender/logic/protection_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const protectionChannel = MethodChannel('digital_defender/protection');
  const statsChannel = MethodChannel('digital_defender/stats');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(protectionChannel, (call) async {
      if (call.method == 'android_start_protection' || call.method == 'android_stop_protection') {
        return null;
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(statsChannel, (call) async {
      if (call.method == 'getStats') {
        return jsonEncode({
          'blockedCount': 1,
          'sessionBlocked': 1,
          'running': true,
          'mode': 'standard',
          'failOpenActive': false,
          'recent': [],
        });
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(protectionChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(statsChannel, null);
  });

  test('turnOnProtection completes and applies native state', () async {
    final controller = ProtectionController(androidOverride: true, windowsOverride: false);

    await controller.turnOnProtection();
    controller.debugHandleNativeState('ON');

    expect(controller.state, ProtectionState.on);
    expect(controller.isCommandInFlight, isFalse);
  });

  test('maps platform exception codes to errors', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(protectionChannel, (call) async {
      throw const PlatformException(code: 'denied', message: 'denied');
    });

    final controller = ProtectionController(androidOverride: true, windowsOverride: false);

    await controller.turnOnProtection();

    expect(controller.state, ProtectionState.error);
    expect(controller.errorCode, 'denied');
  });

  test('command timeout clears in-flight flag', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(protectionChannel, (call) async {
      await Future.delayed(const Duration(milliseconds: 200));
      return null;
    });

    final controller = ProtectionController(
      androidOverride: true,
      windowsOverride: false,
      commandTimeout: const Duration(milliseconds: 50),
    );

    await controller.turnOnProtection();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(controller.isCommandInFlight, isFalse);
    expect(controller.errorMessage, contains('вызов завис'));
  });
}
