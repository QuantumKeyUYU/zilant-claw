import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ProtectionState { off, starting, on, reconnecting, error }

enum ProtectionMode { standard, advanced, ultra }

class ProtectionController extends ChangeNotifier {
  ProtectionController({bool? androidOverride, bool? windowsOverride, Duration commandTimeout = const Duration(seconds: 15)})
      : _isAndroid = androidOverride ?? Platform.isAndroid,
        _isWindows = windowsOverride ?? Platform.isWindows,
        _commandTimeout = commandTimeout {
    _attachEventStream();
  }

  static const MethodChannel _channel =
      MethodChannel('digital_defender/protection');
  static const MethodChannel _statsChannel =
      MethodChannel('digital_defender/stats');
  static const EventChannel _eventsChannel =
      EventChannel('digital_defender/protection_events');

  final bool _isAndroid;
  final bool _isWindows;
  final Duration _commandTimeout;

  ProtectionState _state = ProtectionState.off;
  bool _protectionEnabled = false;
  bool _nsfwEnabled = false;
  bool _focusEnabled = false;
  String? _errorMessage;
  String? _errorCode;
  ProtectionStats _stats = ProtectionStats.empty();
  String? _statsError;
  ProtectionMode _mode = ProtectionMode.standard;
  StreamSubscription<dynamic>? _eventSubscription;
  bool _isCommandInFlight = false;
  Timer? _commandTimeoutTimer;

  ProtectionState get state => _state;
  bool get protectionEnabled => _protectionEnabled;
  bool get nsfwEnabled => _nsfwEnabled;
  bool get focusEnabled => _focusEnabled;
  String? get errorMessage => _errorMessage;
  String? get errorCode => _errorCode;
  ProtectionStats get stats => _stats;
  String? get statsError => _statsError;
  ProtectionMode get mode => _mode;
  bool get isCommandInFlight => _isCommandInFlight;

  Future<void> loadProtectionMode() async {
    if (!_isAndroid) {
      return;
    }
    try {
      final result = await _channel.invokeMethod<String>('getProtectionMode');
      if (result != null) {
        _mode = _stringToMode(result);
        notifyListeners();
      }
    } catch (_) {
      // keep existing mode
    }
  }

  Future<void> setNsfwEnabled(bool enabled) async {
    if (!_protectionEnabled && enabled) {
      return;
    }
    _nsfwEnabled = enabled;
    notifyListeners();
  }

  Future<void> setFocusEnabled(bool enabled) async {
    if (!_protectionEnabled && enabled) {
      return;
    }
    _focusEnabled = enabled;
    if (enabled && !_nsfwEnabled) {
      _nsfwEnabled = true;
    }
    notifyListeners();
  }

  Future<void> setProtectionMode(ProtectionMode newMode) async {
    if (!_isAndroid) {
      _mode = newMode;
      notifyListeners();
      return;
    }
    try {
      final applied = await _channel.invokeMethod<String>(
        'setProtectionMode',
        {'mode': _modeToString(newMode)},
      );
      if (applied != null) {
        _mode = _stringToMode(applied);
      } else {
        _mode = newMode;
      }
      _statsError = null;
      await refreshStats();
    } on PlatformException catch (e) {
      _statsError = e.message ?? 'Не удалось сменить режим защиты.';
      notifyListeners();
    }
  }

  Future<void> toggleProtection() async {
    switch (_state) {
      case ProtectionState.off:
      case ProtectionState.error:
        await turnOnProtection();
        break;
      case ProtectionState.on:
      case ProtectionState.reconnecting:
        await turnOffProtection();
        break;
      case ProtectionState.starting:
        break;
    }
  }

  Future<void> turnOnProtection() async {
    if (!_isAndroid && !_isWindows) {
      _setError('Платформа не поддерживается на этом этапе.');
      return;
    }
    if (_isCommandInFlight) return;
    _markCommandStart('turnOnProtection');
    try {
      if (_isAndroid) {
        await _channel.invokeMethod('android_start_protection');
      } else if (_isWindows) {
        await _channel.invokeMethod('windows_start_protection');
        _updateState(ProtectionState.on);
      }
      _clearError();
      _protectionEnabled = true;
      if (!_isAndroid) {
        _markCommandDone();
      }
      await refreshStats();
    } on PlatformException catch (e) {
      _markCommandDone();
      _setError(_mapPlatformError(e), code: e.code);
      debugPrint('ProtectionController.turnOnProtection platform error: $e');
    } catch (e) {
      _markCommandDone();
      debugPrint('ProtectionController.turnOnProtection error: $e');
      _setError('Не удалось включить защиту. Проверьте разрешения защиты.');
    }
  }

  Future<void> turnOffProtection() async {
    if (!_isAndroid && !_isWindows) {
      _setError('Платформа не поддерживается на этом этапе.');
      return;
    }
    if (_isCommandInFlight) return;
    _markCommandStart('turnOffProtection');
    try {
      if (_isAndroid) {
        await _channel.invokeMethod('android_stop_protection');
      } else if (_isWindows) {
        await _channel.invokeMethod('windows_stop_protection');
        _updateState(ProtectionState.off);
      }
      _protectionEnabled = false;
      if (!_isAndroid) {
        _markCommandDone();
      }
      await refreshStats();
    } on PlatformException catch (e) {
      _markCommandDone();
      _setError(e.message ?? 'Ошибка платформы.', code: e.code);
      debugPrint('ProtectionController.turnOffProtection platform error: $e');
    } catch (e) {
      _markCommandDone();
      debugPrint('ProtectionController.turnOffProtection error: $e');
      _setError('Не удалось выключить защиту.');
    }
  }

  Future<void> refreshStats() async {
    if (!_isAndroid) {
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
        if (decoded['mode'] is String) {
          _mode = _stringToMode(decoded['mode'] as String);
        }
      }
    } catch (e) {
      debugPrint('ProtectionController.refreshStats error: $e');
      _statsError = 'Не удалось получить статистику. Попробуйте ещё раз.';
    }
    notifyListeners();
  }

  Future<void> resetStats() async {
    if (!_isAndroid) {
      _stats = ProtectionStats.empty();
      _statsError = null;
      notifyListeners();
      return;
    }
    try {
      await _statsChannel.invokeMethod('resetStats');
      await refreshStats();
    } catch (e) {
      debugPrint('ProtectionController.resetStats error: $e');
      _statsError = 'Не удалось сбросить статистику. Попробуйте ещё раз.';
      notifyListeners();
    }
  }

  Future<void> resetTodayStats() async {
    await resetStats();
  }

  Future<void> clearRecentBlocks() async {
    if (!_isAndroid) {
      _stats = ProtectionStats(
        blockedCount: _stats.blockedCount,
        totalRequests: _stats.totalRequests,
        sessionBlocked: _stats.sessionBlocked,
        blockedNsfw: _stats.blockedNsfw,
        blockedFocus: _stats.blockedFocus,
        domainBlockFrequency: _stats.domainBlockFrequency,
        recent: const [],
        isRunning: _stats.isRunning,
        mode: _stats.mode,
        failOpenActive: _stats.failOpenActive,
      );
      notifyListeners();
      return;
    }
    try {
      await _statsChannel.invokeMethod('clearRecent');
      await refreshStats();
    } catch (e) {
      debugPrint('ProtectionController.clearRecentBlocks error: $e');
      _statsError = 'Не удалось очистить список доменов. Попробуйте ещё раз.';
      notifyListeners();
    }
  }

  Future<void> requestVpnPermission() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('openVpnSettings');
    } on PlatformException catch (e) {
      debugPrint('ProtectionController.requestVpnPermission platform error: $e');
      _setError(_mapPlatformError(e), code: e.code);
    } catch (e) {
      debugPrint('ProtectionController.requestVpnPermission error: $e');
      _setError('Не удалось открыть настройки VPN.');
    }
  }

  void _updateState(ProtectionState newState) {
    _state = newState;
    _protectionEnabled = newState == ProtectionState.on || newState == ProtectionState.reconnecting;
    if (newState != ProtectionState.error) {
      _clearError();
    }
    notifyListeners();
  }

  void _setError(String message, {String? code}) {
    if (_errorMessage == message && _state == ProtectionState.error) {
      return;
    }
    _state = ProtectionState.error;
    _errorMessage = message;
    _errorCode = code;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    _errorCode = null;
  }

  String _mapPlatformError(PlatformException e) {
    switch (e.code) {
      case 'denied':
        return 'Не хватает разрешения на создание защиты. Разрешите доступ и попробуйте ещё раз.';
      case 'start_failed':
        return 'Не удалось запустить защиту. Попробуйте ещё раз или перезагрузите устройство.';
      default:
        return e.message ?? 'Произошла ошибка на уровне платформы.';
    }
  }

  void _attachEventStream() {
    if (!_isAndroid) return;
    _eventSubscription = _eventsChannel.receiveBroadcastStream().listen(
      _handleNativeState,
      onError: (Object error) {
        _statsError = 'Не удалось синхронизировать состояние защиты.';
        notifyListeners();
      },
    );
  }

  void _handleNativeState(dynamic event) {
    final mappedState = _mapNativeState(event);
    if (mappedState == null) return;
    _state = mappedState;
    _protectionEnabled = mappedState == ProtectionState.on || mappedState == ProtectionState.reconnecting;
    if (mappedState != ProtectionState.error) {
      _clearError();
    }
    _markCommandDone();
    notifyListeners();
  }

  @visibleForTesting
  void debugHandleNativeState(String state) => _handleNativeState(state);

  ProtectionState? _mapNativeState(dynamic raw) {
    if (raw is! String) return null;
    switch (raw.toUpperCase()) {
      case 'OFF':
        return ProtectionState.off;
      case 'STARTING':
        return ProtectionState.starting;
      case 'ON':
        return ProtectionState.on;
      case 'ERROR':
        return ProtectionState.error;
      case 'RECONNECTING':
        return ProtectionState.reconnecting;
      default:
        return null;
    }
  }

  void _markCommandStart(String commandName) {
    _isCommandInFlight = true;
    _commandTimeoutTimer?.cancel();
    _commandTimeoutTimer = Timer(_commandTimeout, () {
      if (_isCommandInFlight) {
        _isCommandInFlight = false;
        _setError('Платформенный вызов завис, попробуйте ещё раз.', code: 'timeout');
        debugPrint('ProtectionController: command $commandName timed out after $_commandTimeout');
      }
    });
    notifyListeners();
  }

  void _markCommandDone() {
    if (_isCommandInFlight) {
      _isCommandInFlight = false;
      _commandTimeoutTimer?.cancel();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _commandTimeoutTimer?.cancel();
    super.dispose();
  }

  ProtectionMode _stringToMode(String raw) {
    switch (raw.toLowerCase()) {
      case 'strict':
      case 'advanced':
        return ProtectionMode.advanced;
      case 'ultra':
        return ProtectionMode.ultra;
      case 'standard':
      default:
        return ProtectionMode.standard;
    }
  }

  String _modeToString(ProtectionMode mode) {
    switch (mode) {
      case ProtectionMode.advanced:
        return 'strict';
      case ProtectionMode.ultra:
        return 'ultra';
      case ProtectionMode.standard:
        return 'standard';
    }
  }
}

class ProtectionStats {
  const ProtectionStats({
    required this.blockedCount,
    required this.totalRequests,
    required this.sessionBlocked,
    required this.recent,
    required this.blockedNsfw,
    required this.blockedFocus,
    required this.domainBlockFrequency,
    required this.isRunning,
    required this.mode,
    required this.failOpenActive,
  });

  final int blockedCount;
  final int totalRequests;
  final int sessionBlocked;
  final int blockedNsfw;
  final int blockedFocus;
  final Map<String, int> domainBlockFrequency;
  final List<BlockedEntry> recent;
  final bool isRunning;
  final ProtectionMode mode;
  final bool failOpenActive;

  int get totalRequestsToday => totalRequests;
  int get blockedTotalToday => blockedCount;
  int get blockedNsfwToday => blockedNsfw;
  int get blockedFocusToday => blockedFocus;
  String get topStalkerDomainToday {
    if (domainBlockFrequency.isEmpty) return '—';
    final sorted = domainBlockFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  // --- ИСПРАВЛЕНИЯ: Геттеры для совместимости с вашим UI ---

  // UI ожидает vpnActive вместо isRunning
  bool get vpnActive => isRunning; 
  
  // UI ожидает totalBlocked вместо blockedCount
  int get totalBlocked => blockedCount; 
  
  // UI ожидает recentDomains вместо recent
  List<BlockedEntry> get recentDomains => recent; 
  
  // UI ожидает строковое название режима
  String get modeName {
    switch (mode) {
      case ProtectionMode.advanced:
        return 'Advanced';
      case ProtectionMode.ultra:
        return 'ULTRA';
      case ProtectionMode.standard:
      default:
        return 'Standard';
    }
  }
  // ---------------------------------------------------------

  factory ProtectionStats.empty() => const ProtectionStats(
        blockedCount: 0,
        totalRequests: 0,
        sessionBlocked: 0,
        blockedNsfw: 0,
        blockedFocus: 0,
        domainBlockFrequency: {},
        recent: [],
        isRunning: false,
        mode: ProtectionMode.standard,
        failOpenActive: false,
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

    final totalRequestsRaw = json['totalRequests'];
    final totalRequests = totalRequestsRaw is int
        ? totalRequestsRaw
        : totalRequestsRaw is num
            ? totalRequestsRaw.toInt()
            : 0;

    final runningRaw = json['running'];
    final isRunning = runningRaw is bool ? runningRaw : false;

    final failOpenRaw = json['failOpenActive'];
    final failOpenActive = failOpenRaw is bool ? failOpenRaw : false;

    final modeRaw = json['mode'];
    final parsedMode = modeRaw is String
        ? () {
            switch (modeRaw.toLowerCase()) {
              case 'strict':
              case 'advanced':
                return ProtectionMode.advanced;
              case 'ultra':
                return ProtectionMode.ultra;
              default:
                return ProtectionMode.standard;
            }
          }()
        : ProtectionMode.standard;

    final blockedNsfwRaw = json['blockedNsfw'];
    final blockedNsfw = blockedNsfwRaw is num ? blockedNsfwRaw.toInt() : 0;

    final blockedFocusRaw = json['blockedFocus'];
    final blockedFocus = blockedFocusRaw is num ? blockedFocusRaw.toInt() : 0;

    final freqRaw = json['domainBlockFrequency'];
    final domainBlockFrequency = <String, int>{};
    if (freqRaw is Map) {
      freqRaw.forEach((key, value) {
        if (key is String && value is num) {
          domainBlockFrequency[key] = value.toInt();
        }
      });
    }

    return ProtectionStats(
      blockedCount: blockedCount,
      totalRequests: totalRequests,
      sessionBlocked: sessionBlocked,
      blockedNsfw: blockedNsfw,
      blockedFocus: blockedFocus,
      domainBlockFrequency: domainBlockFrequency,
      recent: recentEntries,
      isRunning: isRunning,
      mode: parsedMode,
      failOpenActive: failOpenActive,
    );
  }
}

class BlockedEntry {
  const BlockedEntry({required this.domain, required this.timestamp, this.category});

  final String domain;
  final DateTime timestamp;
  final String? category;

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
      category: json['category'] as String?,
    );
  }
}