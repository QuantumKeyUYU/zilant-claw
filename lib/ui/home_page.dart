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
    final isOn = state == ProtectionState.on;
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
            _buildStatsCard(context, stats.blockedCount),
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
                      isOn ? AppStrings.protectionEnabled : AppStrings.protectionDisabled,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isOn ? AppStrings.vpnActive : AppStrings.vpnInactive,
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
                      onChanged: (_) => _toggleProtection(),
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
            if (state == ProtectionState.error &&
                widget.controller.errorMessage != null)
              Text(
                widget.controller.errorMessage!,
                style: const TextStyle(color: Colors.redAccent),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(BuildContext context, int blockedCount) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
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
        error,
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
