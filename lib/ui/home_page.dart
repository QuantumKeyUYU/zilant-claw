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

  Future<void> _changeMode(ProtectionMode mode) async {
    if (_isChangingMode) return;
    setState(() => _isChangingMode = true);
    await widget.controller.setProtectionMode(mode);
    if (mounted) {
      final error = widget.controller.statsError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error ?? AppStrings.modes.changed.replaceFirst('%s', _modeLabel(mode)),
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
            const SizedBox(height: 12),
            _buildProtectionHint(state),
            const SizedBox(height: 18),
            _buildModeSelector(context),
            const SizedBox(height: 16),
            _buildStatsSummary(context, stats, isOn),
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
          Text(
            AppStrings.common.title,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.common.poweredBy,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withOpacity(0.8),
              fontWeight: FontWeight.w600,
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
                    _StateIndicator(
                      state: state,
                      textColor: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isOn
                          ? AppStrings.home.protectionEnabled
                          : AppStrings.home.protectionDisabled,
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

  Widget _buildProtectionHint(ProtectionState state) {
    final text = () {
      switch (state) {
        case ProtectionState.on:
          return AppStrings.home.protectionHintOn;
        case ProtectionState.reconnecting:
          return '${AppStrings.home.protectionHintReconnecting} (${AppStrings.home.reconnectingSoon})';
        case ProtectionState.starting:
          return AppStrings.home.progressTurningOn;
        case ProtectionState.error:
          return AppStrings.home.protectionHintError;
        case ProtectionState.off:
        default:
          return AppStrings.home.protectionHintOff;
      }
    }();
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8)),
    );
  }

  Widget _buildModeSelector(BuildContext context) {
    final currentMode = widget.controller.mode;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
            AppStrings.modes.label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonHideUnderline(
            child: DropdownButton<ProtectionMode>(
              value: currentMode,
              isExpanded: true,
              dropdownColor: colorScheme.surfaceVariant,
              onChanged: _isChangingMode ? null : (mode) => mode != null ? _changeMode(mode) : null,
              items: const [
                ProtectionMode.standard,
                ProtectionMode.advanced,
                ProtectionMode.ultra,
              ]
                  .map(
                    (mode) => DropdownMenuItem(
                      value: mode,
                      child: Text(
                        _modeLabel(mode),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _modeDescription(currentMode),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (currentMode == ProtectionMode.ultra) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppStrings.modes.ultraModeWarning,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.amber.shade800, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsSummary(
      BuildContext context, ProtectionStats stats, bool protectionOn) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final total = stats.totalRequests;
    final blocked = stats.totalBlocked;
    final hasTraffic = protectionOn && total > 0;
    final percent = (hasTraffic && blocked > 0)
        ? ((blocked / total) * 100).round()
        : null;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant
            .withOpacity(colorScheme.brightness == Brightness.dark ? 0.55 : 1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withOpacity(0.25)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.timelapse_outlined, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.activity.title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                if (!hasTraffic)
                  Text(
                    AppStrings.activity.silent,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.85),
                    ),
                  )
                else ...[
                  Text(
                    AppStrings.activity.totalRequests.replaceFirst('%s', total.toString()),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    percent != null
                        ? AppStrings.activity.blockedWithPercent
                            .replaceFirst('%s', blocked.toString())
                            .replaceFirst('%s', percent.toString())
                        : AppStrings.activity.blockedRequests.replaceFirst('%s', blocked.toString()),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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

  String _modeLabel(ProtectionMode mode) {
    switch (mode) {
      case ProtectionMode.standard:
        return AppStrings.modes.standard;
      case ProtectionMode.advanced:
        return AppStrings.modes.strict;
      case ProtectionMode.ultra:
        return AppStrings.modes.ultra;
    }
  }

  String _modeDescription(ProtectionMode mode) {
    switch (mode) {
      case ProtectionMode.standard:
        return AppStrings.modes.hintStandard;
      case ProtectionMode.advanced:
        return AppStrings.modes.hintStrict;
      case ProtectionMode.ultra:
        return AppStrings.modes.hintUltra;
    }
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

class _StateIndicator extends StatelessWidget {
  const _StateIndicator({required this.state, this.textColor});

  final ProtectionState state;
  final Color? textColor;

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
        return AppStrings.stats.stateOn;
      case ProtectionState.starting:
        return AppStrings.stats.stateStarting;
      case ProtectionState.reconnecting:
        return AppStrings.stats.stateReconnecting;
      case ProtectionState.error:
        return AppStrings.stats.stateError;
      case ProtectionState.off:
      default:
        return AppStrings.stats.stateOff;
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = textColor ?? Theme.of(context).colorScheme.onSurfaceVariant;
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
              ?.copyWith(color: labelColor, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
