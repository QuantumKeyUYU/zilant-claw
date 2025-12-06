import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ProtectionState { off, turningOn, on, turningOff, error }

class ProtectionController extends ChangeNotifier {
  ProtectionController();

  static const MethodChannel _channel =
      MethodChannel('digital_defender/protection');

  ProtectionState _state = ProtectionState.off;
  String? _errorMessage;

  ProtectionState get state => _state;
  String? get errorMessage => _errorMessage;

  Future<void> toggleProtection() async {
    switch (_state) {
      case ProtectionState.off:
      case ProtectionState.error:
        await turnOnProtection();
        break;
      case ProtectionState.on:
        await turnOffProtection();
        break;
      case ProtectionState.turningOn:
      case ProtectionState.turningOff:
        break;
    }
  }

  Future<void> turnOnProtection() async {
    if (_state != ProtectionState.off && _state != ProtectionState.error) {
      return;
    }
    if (!Platform.isAndroid && !Platform.isWindows) {
      _setError('Платформа не поддерживается на этом этапе.');
      return;
    }
    _updateState(ProtectionState.turningOn);
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('android_start_protection');
      } else if (Platform.isWindows) {
        await _channel.invokeMethod('windows_start_protection');
      }
      _updateState(ProtectionState.on);
    } on PlatformException catch (e) {
      _setError(e.message ?? 'Ошибка платформы.');
    } catch (_) {
      _setError('Не удалось включить защиту. Проверь разрешения VPN.');
    }
  }

  Future<void> turnOffProtection() async {
    if (_state != ProtectionState.on) {
      return;
    }
    if (!Platform.isAndroid && !Platform.isWindows) {
      _setError('Платформа не поддерживается на этом этапе.');
      return;
    }
    _updateState(ProtectionState.turningOff);
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('android_stop_protection');
      } else if (Platform.isWindows) {
        await _channel.invokeMethod('windows_stop_protection');
      }
      _updateState(ProtectionState.off);
    } on PlatformException catch (e) {
      _setError(e.message ?? 'Ошибка платформы.');
    } catch (_) {
      _setError('Не удалось выключить защиту.');
    }
  }

  void _updateState(ProtectionState newState) {
    _state = newState;
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String message) {
    _state = ProtectionState.error;
    _errorMessage = message;
    notifyListeners();
  }
}
