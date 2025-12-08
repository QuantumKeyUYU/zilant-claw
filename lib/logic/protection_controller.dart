import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ProtectionState { off, turningOn, on, turningOff, error }

class ProtectionController extends ChangeNotifier {
  ProtectionController();

  static const MethodChannel _channel =
      MethodChannel('digital_defender/protection');
  static const MethodChannel _statsChannel =
      MethodChannel('digital_defender/stats');

  ProtectionState _state = ProtectionState.off;
  String? _errorMessage;
  String? _errorCode;
  ProtectionStats _stats = ProtectionStats.empty();
  String? _statsError;

  ProtectionState get state => _state;
  String? get errorMessage => _errorMessage;
  String? get errorCode => _errorCode;
  ProtectionStats get stats => _stats;
  String? get statsError => _statsError;

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
      await refreshStats();
    } on PlatformException catch (e) {
      _setError(_mapPlatformError(e), code: e.code);
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
      await refreshStats();
    } on PlatformException catch (e) {
      _setError(e.message ?? 'Ошибка платформы.', code: e.code);
    } catch (_) {
      _setError('Не удалось выключить защиту.');
    }
  }

  Future<void> refreshStats() async {
    if (!Platform.isAndroid) {
      _stats = ProtectionStats.empty();
      _statsError = null;
      notifyListeners();
      return;
    }
    try {
      final result = await _statsChannel.invokeMethod<String>('getStats');
      if (result != null) {
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        _stats = ProtectionStats.fromJson(decoded);
        _statsError = null;
        _syncStateWithStats();
      }
    } catch (e) {
      _statsError = 'Не удалось получить статистику. Попробуйте ещё раз.';
    }
    notifyListeners();
  }

  Future<void> resetStats() async {
    if (!Platform.isAndroid) {
      _stats = ProtectionStats.empty();
      _statsError = null;
      notifyListeners();
      return;
    }
    try {
      await _statsChannel.invokeMethod('resetStats');
      await refreshStats();
    } catch (e) {
      _statsError = 'Не удалось сбросить статистику. Попробуйте ещё раз.';
      notifyListeners();
    }
  }

  void _updateState(ProtectionState newState) {
    _state = newState;
    _errorMessage = null;
    _errorCode = null;
    notifyListeners();
  }

  void _setError(String message, {String? code}) {
    _state = ProtectionState.error;
    _errorMessage = message;
    _errorCode = code;
    notifyListeners();
  }

  String _mapPlatformError(PlatformException e) {
    switch (e.code) {
      case 'denied':
        return 'Не хватает разрешения на создание VPN. Разрешите доступ и попробуйте ещё раз.';
      case 'start_failed':
        return 'Не удалось запустить VPN. Попробуйте ещё раз или перезагрузите устройство.';
      default:
        return e.message ?? 'Произошла ошибка на уровне платформы.';
    }
  }

  void _syncStateWithStats() {
    final running = _stats.isRunning;
    if (running && _state == ProtectionState.turningOn) {
      _state = ProtectionState.on;
      _errorMessage = null;
      _errorCode = null;
    } else if (!running && _state == ProtectionState.turningOff) {
      _state = ProtectionState.off;
    } else if (running && _state == ProtectionState.error) {
      _state = ProtectionState.on;
      _errorMessage = null;
      _errorCode = null;
    } else if (!running && _state == ProtectionState.error) {
      _state = ProtectionState.off;
    } else if (running && _state == ProtectionState.off) {
      _state = ProtectionState.on;
    } else if (!running && _state == ProtectionState.on) {
      _state = ProtectionState.off;
    }
  }
}

class ProtectionStats {
  const ProtectionStats({
    required this.blockedCount,
    required this.sessionBlocked,
    required this.recent,
    required this.isRunning,
  });

  final int blockedCount;
  final int sessionBlocked;
  final List<BlockedEntry> recent;
  final bool isRunning;

  factory ProtectionStats.empty() => const ProtectionStats(
        blockedCount: 0,
        sessionBlocked: 0,
        recent: [],
        isRunning: false,
      );

  factory ProtectionStats.fromJson(Map<String, dynamic> json) {
    final recentRaw = json['recent'];
    final recentEntries = <BlockedEntry>[];
    if (recentRaw is List) {
      for (final item in recentRaw) {
        if (item is Map<String, dynamic>) {
          recentEntries.add(BlockedEntry.fromJson(item));
        }
      }
    }

    final countRaw = json['blockedCount'];
    final blockedCount = countRaw is int
        ? countRaw
        : countRaw is num
            ? countRaw.toInt()
            : 0;

    final sessionRaw = json['sessionBlocked'];
    final sessionBlocked = sessionRaw is int
        ? sessionRaw
        : sessionRaw is num
            ? sessionRaw.toInt()
            : 0;

    final runningRaw = json['running'];
    final isRunning = runningRaw is bool ? runningRaw : false;

    return ProtectionStats(
      blockedCount: blockedCount,
      sessionBlocked: sessionBlocked,
      recent: recentEntries,
      isRunning: isRunning,
    );
  }
}

class BlockedEntry {
  const BlockedEntry({required this.domain, required this.timestamp});

  final String domain;
  final DateTime timestamp;

  factory BlockedEntry.fromJson(Map<String, dynamic> json) {
    final timestampRaw = json['timestamp'];
    final ts = timestampRaw is int
        ? timestampRaw
        : timestampRaw is num
            ? timestampRaw.toInt()
            : 0;
    return BlockedEntry(
      domain: (json['domain'] as String?) ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
    );
  }
}
