import 'dart:async';
import 'dart:math';

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
            icon: const Icon(Icons.info_outline),
            tooltip: AppStrings.common.protectionInfoLink,
            onPressed: () => _openProtectionInfo(context),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshStats,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildHeroCard(context, isOn, isBusy, state, failOpenActive),
            const SizedBox(height: 16),
            _buildAttentionPanel(context, stats),
            const SizedBox(height: 16),
            _buildDetoxModes(context, isOn),
            const SizedBox(height: 12),
            _buildStatsActions(context),
            const SizedBox(height: 12),
            _buildStoryTile(context, stats),
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

  Widget _buildHeroCard(
    BuildContext context,
    bool isOn,
    bool isBusy,
    ProtectionState state,
    bool failOpen,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final needsPermission = widget.controller.errorCode == 'denied';
    final errorMessage = widget.controller.errorMessage;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOn ? AppStrings.home.protectionOnTitle : AppStrings.home.protectionOffTitle,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _subtitleForState(
                        state,
                        needsPermission ? AppStrings.home.permissionRequired : errorMessage,
                        isOn,
                      ),
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer.withOpacity(0.9),
                        fontWeight: FontWeight.w600,
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
                    activeColor: colorScheme.onPrimaryContainer,
                  ),
                  if (isBusy)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isOn ? AppStrings.home.protectionOn : AppStrings.home.protectionOff,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (failOpen) ...[
            const SizedBox(height: 10),
            Text(
              AppStrings.home.protectionFailOpenWarning,
              style: textTheme.bodySmall?.copyWith(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (state == ProtectionState.error && errorMessage != null) ...[
            const SizedBox(height: 12),
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
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAttentionPanel(BuildContext context, ProtectionStats stats) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final total = stats.totalRequestsToday;
    final tracking = stats.trackingAttempts;
    final attention = stats.attentionAttempts;
    final topStalker = stats.topStalkerDomainToday;
    final noise = _noiseLabel(tracking + attention);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(colorScheme.brightness == Brightness.dark ? 0.55 : 1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outline.withOpacity(0.15)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.home.todayHeader,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _MetricRow(
            label: AppStrings.home.todayTotalRequests.replaceFirst('%d', total.toString()),
            textTheme: textTheme,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          _MetricRow(
            label: AppStrings.home.todayTrackingAttempts.replaceFirst('%d', tracking.toString()),
            textTheme: textTheme,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          _MetricRow(
            label: AppStrings.home.todayAttentionAttempts.replaceFirst('%d', attention.toString()),
            textTheme: textTheme,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          _MetricRow(
            label: AppStrings.home.todayTopStalker.replaceFirst('%s', topStalker),
            textTheme: textTheme,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          _MetricRow(
            label: AppStrings.home.todayNoiseLevel.replaceFirst('%s', noise),
            textTheme: textTheme,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildDetoxModes(BuildContext context, bool protectionOn) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final cleanEnabled = widget.controller.cleanEnabled;
    final focusEnabled = widget.controller.focusEnabled;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(colorScheme.brightness == Brightness.dark ? 0.5 : 1),
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
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _DetoxTile(
            title: AppStrings.home.cleanTitle,
            subtitle: AppStrings.home.cleanSubtitle,
            hint: AppStrings.home.cleanHint,
            value: cleanEnabled,
            enabled: protectionOn,
            onChanged: (value) => widget.controller.setCleanEnabled(value),
          ),
          const SizedBox(height: 12),
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

  Widget _buildStoryTile(BuildContext context, ProtectionStats stats) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final story = _pickStory(stats);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.home.storiesTitle,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  story,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

  String _noiseLabel(int intensity) {
    if (intensity > 80) return AppStrings.home.noiseHigh;
    if (intensity > 30) return AppStrings.home.noiseElevated;
    return AppStrings.home.noiseCalm;
  }

  String _pickStory(ProtectionStats stats) {
    final rand = Random(DateTime.now().millisecondsSinceEpoch);
    if (stats.blockedFocus > 0) {
      final template = AppStrings.home.storyFocusBursts[rand.nextInt(AppStrings.home.storyFocusBursts.length)];
      if (template.contains('%d')) {
        return template.replaceFirst('%d', stats.blockedFocus.toString());
      }
      return template;
    }
    if (stats.trackingAttempts > 0 || stats.blockedClean > 0) {
      final template = AppStrings.home.storyTracking[rand.nextInt(AppStrings.home.storyTracking.length)];
      return template;
    }
    return AppStrings.home.storyQuiet;
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.textTheme, required this.color});

  final String label;
  final TextTheme textTheme;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: textTheme.bodyLarge?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
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
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hint,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.65),
                  fontWeight: FontWeight.w600,
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
