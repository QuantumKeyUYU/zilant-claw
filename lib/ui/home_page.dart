import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/protection_controller.dart';
import 'stats_page.dart';
import 'strings.dart';
import 'protection_info_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final ProtectionController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isRefreshing = false;
  bool _isChangingMode = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    unawaited(widget.controller.refreshStats());
    unawaited(widget.controller.loadProtectionMode());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {});
  }

  Future<void> _toggleProtection() async {
    await widget.controller.toggleProtection();
  }

  Future<void> _refreshStats() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    await widget.controller.refreshStats();
    setState(() => _isRefreshing = false);
  }

  Future<void> _resetStats() async {
    await widget.controller.resetStats();
  }

  Future<void> _openProtectionInfo(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProtectionInfoPage(mode: widget.controller.mode),
      ),
    );
  }

  Future<void> _goToStats(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatsPage(controller: widget.controller),
      ),
    );
    await widget.controller.refreshStats();
  }

  Future<void> _changeMode(ProtectionMode mode) async {
    if (_isChangingMode) return;
    setState(() => _isChangingMode = true);
    await widget.controller.setProtectionMode(mode);
    if (mounted) {
      final error = widget.controller.statsError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error ?? AppStrings.protectionModeChanged.replaceFirst('%s', _modeLabel(mode)),
          ),
        ),
      );
    }
    setState(() => _isChangingMode = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final stats = widget.controller.stats;
    final isOn = state == ProtectionState.on || state == ProtectionState.reconnecting;
    final failOpenActive = stats.failOpenActive;
    final isBusy = widget.controller.isCommandInFlight || state == ProtectionState.starting;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.title),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.verified_user_outlined),
            tooltip: AppStrings.openPrivacyGuide,
            onPressed: () => _openProtectionInfo(context),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshStats,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildProtectionCard(context, isOn, isBusy, state, failOpenActive),
            const SizedBox(height: 8),
            _buildProtectionHint(state),
            const SizedBox(height: 16),
            _buildModeSelector(context),
            const SizedBox(height: 16),
            _buildStatsSummary(context, stats.blockedCount, stats.sessionBlocked),
            const SizedBox(height: 12),
            _buildStatsActions(context),
            if (widget.controller.statsError != null) ...[
              const SizedBox(height: 12),
              Text(
                widget.controller.statsError!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProtectionCard(
    BuildContext context,
    bool isOn,
    bool isBusy,
    ProtectionState state,
    bool failOpenActive,
  ) {
    final errorMessage = widget.controller.errorMessage;
    final needsPermission = widget.controller.errorCode == 'denied';

    final title = _titleForState(state, isOn);
    final subtitle = _subtitleForState(state, errorMessage, isOn);

    return Card(
      color: Colors.blueGrey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _StateIndicator(state: state),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Switch.adaptive(
                      value: isOn || state == ProtectionState.starting,
                      onChanged: isBusy ? null : (_) => _toggleProtection(),
                      activeColor: Colors.greenAccent,
                    ),
                    if (isBusy)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(
                              isOn ? Colors.greenAccent : Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (failOpenActive) ...[
              const SizedBox(height: 10),
              Text(
                AppStrings.protectionFailOpenWarning,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.amber.shade200, fontWeight: FontWeight.w600),
              ),
            ],
            if (state == ProtectionState.error && errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                errorMessage,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: needsPermission
                    ? ElevatedButton(
                        onPressed: _toggleProtection,
                        child: const Text(AppStrings.grantVpnPermission),
                      )
                    : ElevatedButton(
                        onPressed: _toggleProtection,
                        child: const Text(AppStrings.retryStart),
                      ),
              )
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProtectionHint(ProtectionState state) {
    final text = () {
      switch (state) {
        case ProtectionState.on:
          return AppStrings.protectionHintOn;
        case ProtectionState.reconnecting:
          return AppStrings.protectionHintReconnecting;
        case ProtectionState.starting:
          return AppStrings.progressTurningOn;
        case ProtectionState.error:
          return AppStrings.protectionHintError;
        case ProtectionState.off:
        default:
          return AppStrings.protectionHintOff;
      }
    }();
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
    );
  }

  Widget _buildModeSelector(BuildContext context) {
    final currentMode = widget.controller.mode;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.protectionModeLabel,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButton<ProtectionMode>(
              value: currentMode,
              isExpanded: true,
              onChanged: _isChangingMode ? null : (mode) => mode != null ? _changeMode(mode) : null,
              items: const [
                ProtectionMode.standard,
                ProtectionMode.advanced,
                ProtectionMode.ultra,
              ]
                  .map(
                    (mode) => DropdownMenuItem(
                      value: mode,
                      child: Text(_modeLabel(mode)),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 6),
            Text(
              _modeDescription(currentMode),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey.shade700, fontWeight: FontWeight.w500),
            ),
            if (currentMode == ProtectionMode.advanced ||
                currentMode == ProtectionMode.ultra) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        currentMode == ProtectionMode.ultra
                            ? AppStrings.ultraModeWarning
                            : AppStrings.strictModeWarning,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.amber.shade800, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSummary(BuildContext context, int blockedCount, int sessionBlocked) {
    final summary = AppStrings.blockedCompact
        .replaceFirst('%s', sessionBlocked.toString())
        .replaceFirst('%s', blockedCount.toString());

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.shield, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                summary,
                style:
                    Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (_isRefreshing)
              const SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => _goToStats(context),
            child: const Text(AppStrings.details),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _resetStats,
            icon: const Icon(Icons.delete_outline),
            label: const Text(AppStrings.resetStats),
          ),
        ),
      ],
    );
  }

  String _modeLabel(ProtectionMode mode) {
    switch (mode) {
      case ProtectionMode.standard:
        return AppStrings.protectionModeStandard;
      case ProtectionMode.advanced:
        return AppStrings.protectionModeStrict;
      case ProtectionMode.ultra:
        return AppStrings.protectionModeUltra;
    }
  }

  String _modeDescription(ProtectionMode mode) {
    switch (mode) {
      case ProtectionMode.standard:
        return AppStrings.protectionModeHintStandard;
      case ProtectionMode.advanced:
        return AppStrings.protectionModeHintStrict;
      case ProtectionMode.ultra:
        return AppStrings.protectionModeHintUltra;
    }
  }

  String _titleForState(ProtectionState state, bool isOn) {
    switch (state) {
      case ProtectionState.starting:
        return AppStrings.protectionTurningOn;
      case ProtectionState.reconnecting:
        return AppStrings.protectionReconnecting;
      case ProtectionState.error:
        return AppStrings.protectionUnknown;
      case ProtectionState.on:
      case ProtectionState.off:
      default:
        return isOn ? AppStrings.protectionEnabled : AppStrings.protectionDisabled;
    }
  }

  String _subtitleForState(
    ProtectionState state,
    String? errorMessage,
    bool isOn,
  ) {
    switch (state) {
      case ProtectionState.starting:
        return AppStrings.progressTurningOn;
      case ProtectionState.reconnecting:
        return AppStrings.protectionReconnectingHint;
      case ProtectionState.error:
        return errorMessage ?? AppStrings.progressError;
      case ProtectionState.on:
      case ProtectionState.off:
      default:
        return isOn ? AppStrings.vpnActive : AppStrings.vpnInactive;
    }
  }
}

class _StateIndicator extends StatelessWidget {
  const _StateIndicator({required this.state});

  final ProtectionState state;

  Color _colorForState() {
    switch (state) {
      case ProtectionState.on:
        return Colors.greenAccent;
      case ProtectionState.starting:
      case ProtectionState.reconnecting:
        return Colors.amberAccent;
      case ProtectionState.error:
        return Colors.redAccent;
      case ProtectionState.off:
      default:
        return Colors.white70;
    }
  }

  String _labelForState() {
    switch (state) {
      case ProtectionState.on:
        return AppStrings.stateOn;
      case ProtectionState.starting:
        return AppStrings.stateStarting;
      case ProtectionState.reconnecting:
        return AppStrings.stateReconnecting;
      case ProtectionState.error:
        return AppStrings.stateError;
      case ProtectionState.off:
      default:
        return AppStrings.stateOff;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: _colorForState()),
        const SizedBox(width: 6),
        Text(
          _labelForState(),
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
