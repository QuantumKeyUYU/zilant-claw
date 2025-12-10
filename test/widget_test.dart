import 'package:digital_defender/logic/protection_controller.dart';
import 'package:digital_defender/main.dart';
import 'package:digital_defender/ui/home_page.dart';
import 'package:digital_defender/ui/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeProtectionController extends ProtectionController {
  FakeProtectionController({
    required ProtectionState initialState,
    required ProtectionStats stats,
    ProtectionMode mode = ProtectionMode.standard,
    String? errorMessage,
    String? errorCode,
  })  : _fakeState = initialState,
        _fakeStats = stats,
        _fakeMode = mode,
        _fakeError = errorMessage,
        _fakeErrorCode = errorCode,
        super(androidOverride: false, windowsOverride: false);

  ProtectionState _fakeState;
  ProtectionStats _fakeStats;
  ProtectionMode _fakeMode;
  String? _fakeError;
  String? _fakeErrorCode;

  @override
  ProtectionState get state => _fakeState;

  @override
  ProtectionStats get stats => _fakeStats;

  @override
  ProtectionMode get mode => _fakeMode;

  @override
  String? get errorMessage => _fakeError;

  @override
  String? get errorCode => _fakeErrorCode;

  @override
  bool get isCommandInFlight => false;

  @override
  Future<void> refreshStats() async {}

  @override
  Future<void> loadProtectionMode() async {}

  @override
  Future<void> toggleProtection() async {}
}

void main() {
  testWidgets('DigitalDefenderApp renders with protection disabled by default', (tester) async {
    await tester.pumpWidget(const DigitalDefenderApp());
    await tester.pumpAndSettle();

    expect(find.textContaining(AppStrings.home.protectionDisabled), findsOneWidget);
  });

  testWidgets('HomePage shows active state information', (tester) async {
    final controller = FakeProtectionController(
      initialState: ProtectionState.on,
      stats: const ProtectionStats(
        blockedCount: 5,
        sessionBlocked: 2,
        recent: [],
        isRunning: true,
        mode: ProtectionMode.advanced,
        failOpenActive: false,
      ),
      mode: ProtectionMode.advanced,
    );

    await tester.pumpWidget(MaterialApp(home: HomePage(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.home.protectionEnabled), findsOneWidget);
    expect(find.text(AppStrings.stats.stateOn), findsWidgets);
  });
}
