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
    await widget.controller.resetTodayStats();
  }

  Future<void> _requestVpnPermission() async {
    await widget.controller.requestVpnPermission();
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

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final stats = widget.controller.stats;
    final isOn = widget.controller.protectionEnabled;
    final failOpenActive = stats.failOpenActive;
    final isBusy = widget.controller.isCommandInFlight || state == ProtectionState.starting;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.common.title),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: AppStrings.common.openPrivacyGuide,
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
            const SizedBox(height: 16),
            _buildDetoxModes(context, isOn),
            const SizedBox(height: 16),
            _buildTodayStats(context, stats),
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

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant
            .withOpacity(colorScheme.brightness == Brightness.dark ? 0.6 : 1),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  AppStrings.common.title,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.common.poweredBy,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusIndicator(
                      active: isOn,
                      textColor: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isOn
                          ? AppStrings.home.protectionOnTitle
                          : AppStrings.home.protectionOffTitle,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subtitleForState(
                        state,
                        needsPermission ? AppStrings.home.permissionRequired : errorMessage,
                        isOn,
                      ),
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant.withOpacity(0.85),
                        fontWeight: FontWeight.w500,
                      ),
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
                    activeColor: colorScheme.primary,
                  ),
                  if (isBusy)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (failOpenActive) ...[
            const SizedBox(height: 14),
            Text(
              AppStrings.home.protectionFailOpenWarning,
              style: textTheme.bodySmall?.copyWith(
                color: Colors.amber.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (state == ProtectionState.error && errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              errorMessage,
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: needsPermission
                  ? ElevatedButton(
                      onPressed: _requestVpnPermission,
                      child: Text(AppStrings.actions.openVpnSettings),
                    )
                  : ElevatedButton(
                      onPressed: _toggleProtection,
                      child: Text(AppStrings.actions.retryStart),
                    ),
            )
          ],
        ],
      ),
    );
  }

  Widget _buildDetoxModes(BuildContext context, bool protectionOn) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final nsfwEnabled = widget.controller.nsfwEnabled;
    final focusEnabled = widget.controller.focusEnabled;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant
            .withOpacity(colorScheme.brightness == Brightness.dark ? 0.55 : 1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.home.detoxHeader,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _DetoxTile(
            title: AppStrings.home.nsfwTitle,
            subtitle: AppStrings.home.nsfwSubtitle,
            hint: AppStrings.home.nsfwHint,
            value: nsfwEnabled,
            enabled: protectionOn,
            onChanged: (value) => widget.controller.setNsfwEnabled(value),
          ),
          const SizedBox(height: 10),
          _DetoxTile(
            title: AppStrings.home.focusTitle,
            subtitle: AppStrings.home.focusSubtitle,
            hint: AppStrings.home.focusHint,
            value: focusEnabled,
            enabled: protectionOn,
            onChanged: (value) => widget.controller.setFocusEnabled(value),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayStats(BuildContext context, ProtectionStats stats) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final total = stats.totalRequestsToday;
    final blocked = stats.blockedTotalToday;
    final topStalker = stats.topStalkerDomainToday;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant
            .withOpacity(colorScheme.brightness == Brightness.dark ? 0.55 : 1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withOpacity(0.25)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.home.todayHeader,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.home.todayTotalRequests.replaceFirst('%d', total.toString()),
            style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.home.todayBlocked.replaceFirst('%d', blocked.toString()),
            style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.home.todayTopStalker.replaceFirst('%s', topStalker),
            style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final padding = const EdgeInsets.symmetric(vertical: 14);
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              shape: shape,
              padding: padding,
            ),
            onPressed: () => _goToStats(context),
            child: Text(AppStrings.stats.details),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              shape: shape,
              padding: padding,
              side: BorderSide(color: colorScheme.primary),
              foregroundColor: colorScheme.primary,
            ),
            onPressed: _resetStats,
            child: Text(AppStrings.stats.resetStats),
          ),
        ),
      ],
    );
  }

  String _subtitleForState(
    ProtectionState state,
    String? errorMessage,
    bool isOn,
  ) {
    switch (state) {
      case ProtectionState.starting:
        return AppStrings.home.progressTurningOn;
      case ProtectionState.reconnecting:
        return AppStrings.home.protectionReconnectingHint;
      case ProtectionState.error:
        return errorMessage ?? AppStrings.home.progressError;
      case ProtectionState.on:
      case ProtectionState.off:
      default:
        return isOn
            ? AppStrings.home.protectionSubtitleOn
            : AppStrings.home.protectionSubtitleOff;
    }
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.active, this.textColor});

  final bool active;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelColor = textColor ?? colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: active ? Colors.greenAccent : Colors.grey),
        const SizedBox(width: 6),
        Text(
          active ? AppStrings.home.statusOn : AppStrings.home.statusOff,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: labelColor, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _DetoxTile extends StatelessWidget {
  const _DetoxTile({
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final String hint;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.85),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hint,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.65),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeColor: colorScheme.primary,
        ),
      ],
    );
  }
}
