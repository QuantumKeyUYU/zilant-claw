import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/protection_controller.dart';
import 'strings.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.controller});

  final ProtectionController controller;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    unawaited(widget.controller.refreshStats());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {});
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    await widget.controller.refreshStats();
    setState(() => _isRefreshing = false);
  }

  Future<void> _clearRecent() async {
    await widget.controller.clearRecentBlocks();
    await widget.controller.refreshStats();
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.controller.stats;
    final state = widget.controller.state;
    final isRunning =
        stats.isRunning || state == ProtectionState.on || state == ProtectionState.turningOn;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.statsHeaderTitle),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusCard(
              context,
              isRunning,
              stats.blockedCount,
              stats.sessionBlocked,
              stats.failOpenActive,
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.recentTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _buildRecentList(context),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _clearRecent,
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text(AppStrings.clearRecent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, bool isRunning, int blocked,
      int sessionBlocked, bool failOpenActive) {
    final icon = isRunning ? Icons.shield : Icons.shield_outlined;
    final iconColor = isRunning ? Colors.green : Colors.blueGrey;
    final statusText = isRunning ? AppStrings.vpnActive : AppStrings.vpnInactive;
    final modeText = AppStrings.modeStatus.replaceFirst('%s', _modeLabel(widget.controller.mode));
    final filterText = failOpenActive
        ? AppStrings.filterStatusFailOpen
        : AppStrings.filterStatusActive;
    final filterStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: failOpenActive ? Colors.orange.shade700 : Colors.green.shade700,
          fontWeight: FontWeight.w600,
        );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  modeText,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(filterText, style: filterStyle),
              ],
            ),
          ),
            if (_isRefreshing)
              const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.sessionLabel,
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    '$sessionBlocked',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.totalLabel,
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    '$blocked',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentList(BuildContext context) {
    final entries = widget.controller.stats.recent.reversed.toList();
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          AppStrings.recentEmpty,
        ),
      );
    }

    return Column(
      children: entries
          .map(
            (entry) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.public),
              title: Text(entry.domain),
              subtitle: Text(_formatTimestamp(entry.timestamp)),
            ),
          )
          .toList(),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays >= 1) {
      final dayLabel = difference.inDays == 1
          ? AppStrings.yesterday
          : '${difference.inDays} ${AppStrings.daysAgoSuffix}';
      final time = _twoDigits(timestamp.hour) + ':' + _twoDigits(timestamp.minute);
      return '$dayLabel $time';
    }

    return '${_twoDigits(timestamp.hour)}:${_twoDigits(timestamp.minute)}';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

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
