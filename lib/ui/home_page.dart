import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/protection_controller.dart';
import 'strings.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final ProtectionController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final stats = widget.controller.stats;
    final isOn =
        stats.isRunning || state == ProtectionState.on || state == ProtectionState.turningOn;
    final isBusy =
        state == ProtectionState.turningOn || state == ProtectionState.turningOff;

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
            const SizedBox(height: 16),
            _buildStatsCard(context, stats.blockedCount, stats.sessionBlocked),
            const SizedBox(height: 12),
            _buildStatsActions(context),
            const SizedBox(height: 24),
            _buildRecentHeader(context),
            const SizedBox(height: 12),
            _buildRecentList(context),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                  ],
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
            const SizedBox(height: 12),
            if (state == ProtectionState.error && errorMessage != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    errorMessage,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (needsPermission)
                        ElevatedButton(
                          onPressed: _toggleProtection,
                          child: const Text(AppStrings.grantVpnPermission),
                        ),
                      if (!needsPermission)
                        ElevatedButton(
                          onPressed: _toggleProtection,
                          child: const Text(AppStrings.retryStart),
                        ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(
      BuildContext context, int blockedCount, int sessionBlocked) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.shield, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.totalBlocked,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$blockedCount',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
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
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.schedule, color: Colors.blueGrey),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.sessionBlocked,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('$sessionBlocked',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                )
              ],
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
          child: ElevatedButton.icon(
            onPressed: _refreshStats,
            icon: const Icon(Icons.refresh),
            label: const Text(AppStrings.refreshStats),
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

  Widget _buildRecentHeader(BuildContext context) {
    final error = widget.controller.statsError;
    if (error != null) {
      return Text(
        '${AppStrings.statsError}\n$error',
        style: const TextStyle(color: Colors.redAccent),
      );
    }
    return Text(
      AppStrings.recentTitle,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildRecentList(BuildContext context) {
    final entries = widget.controller.stats.recent.take(20).toList();
    if (entries.isEmpty) {
      if (widget.controller.stats.blockedCount == 0) {
        return const Text(AppStrings.nothingBlocked);
      }
      return const Text(AppStrings.noRecentBlocks);
    }

    return Column(
      children: entries
          .map(
            (entry) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.public),
              title: Text(entry.domain, style: const TextStyle(fontSize: 16)),
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
}
