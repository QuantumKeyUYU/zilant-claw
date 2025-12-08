import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/protection_controller.dart';
import 'stats_page.dart';
import 'strings.dart';

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
    final isOn =
        stats.isRunning || state == ProtectionState.on || state == ProtectionState.turningOn;
    final isBusy = state == ProtectionState.turningOn || state == ProtectionState.turningOff;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.title),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refreshStats,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildProtectionCard(context, isOn, isBusy, state),
            const SizedBox(height: 12),
            _buildModeSelector(context),
            const SizedBox(height: 12),
            _buildStatsSummary(context, stats.blockedCount, stats.sessionBlocked),
            if (widget.controller.statsError != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.controller.statsError!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 8),
            _buildStatsActions(context),
            const SizedBox(height: 16),
            _buildRecentPreview(context),
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
  ) {
    final errorMessage = widget.controller.errorMessage;
    final needsPermission = widget.controller.errorCode == 'denied';

    String title;
    switch (state) {
      case ProtectionState.turningOn:
        title = AppStrings.protectionTurningOn;
        break;
      case ProtectionState.turningOff:
        title = AppStrings.protectionTurningOff;
        break;
      case ProtectionState.error:
        title = AppStrings.protectionUnknown;
        break;
      default:
        title = isOn ? AppStrings.protectionEnabled : AppStrings.protectionDisabled;
    }

    String subtitle;
    switch (state) {
      case ProtectionState.turningOn:
        subtitle = AppStrings.progressTurningOn;
        break;
      case ProtectionState.turningOff:
        subtitle = AppStrings.progressTurningOff;
        break;
      case ProtectionState.error:
        subtitle = errorMessage ?? AppStrings.progressError;
        break;
      default:
        subtitle = isOn ? AppStrings.vpnActive : AppStrings.vpnInactive;
    }

    return Card(
      color: Colors.blueGrey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                  if (state == ProtectionState.error && errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorMessage,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                    const SizedBox(height: 6),
                    if (needsPermission)
                      ElevatedButton(
                        onPressed: _toggleProtection,
                        child: const Text(AppStrings.grantVpnPermission),
                      )
                    else
                      ElevatedButton(
                        onPressed: _toggleProtection,
                        child: const Text(AppStrings.retryStart),
                      )
                  ],
                ],
              ),
            ),
            Column(
              children: [
                Switch.adaptive(
                  value: isOn,
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
      ),
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
              items: ProtectionMode.values
                  .map(
                    (mode) => DropdownMenuItem(
                      value: mode,
                      child: Text(_modeLabel(mode)),
                    ),
                  )
                  .toList(),
            ),
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

  Widget _buildRecentPreview(BuildContext context) {
    final entries = widget.controller.stats.recent;
    if (entries.isEmpty) {
      if (widget.controller.stats.blockedCount == 0) {
        return const Text(AppStrings.nothingBlocked);
      }
      return const Text(AppStrings.noRecentBlocks);
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            AppStrings.recentPreview.replaceFirst('%d', entries.length.toString()),
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(
          onPressed: () => _goToStats(context),
          child: const Text(AppStrings.details),
        ),
      ],
    );
  }

  String _modeLabel(ProtectionMode mode) {
    switch (mode) {
      case ProtectionMode.light:
        return AppStrings.protectionModeLight;
      case ProtectionMode.standard:
        return AppStrings.protectionModeStandard;
      case ProtectionMode.strict:
        return AppStrings.protectionModeStrict;
    }
  }
}
