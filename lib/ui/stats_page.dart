import 'package:flutter/material.dart';

import '../logic/protection_controller.dart';
import 'strings.dart';

class StatsPage extends StatefulWidget {
  final ProtectionController controller;

  const StatsPage({Key? key, required this.controller}) : super(key: key);

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    setState(() {});
  }

  void _showRecent(BuildContext context, List<BlockedEntry> items) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.recent.header, style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 8),
                    itemBuilder: (_, index) {
                      final entry = items.reversed.elementAt(index);
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.public, size: 20),
                        title: Text(entry.domain),
                        subtitle: Text(_formatTimestamp(entry.timestamp)),
                      );
                    },
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).maybePop();
                      widget.controller.clearRecentBlocks();
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: Text(AppStrings.actions.clearRecent),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);

    if (diff.inMinutes < 1) return AppStrings.recent.timestampJustNow;

    if (now.day == local.day && now.month == local.month && now.year == local.year) {
      return _formatTime(local);
    }

    final yesterday = now.subtract(const Duration(days: 1));
    if (yesterday.day == local.day && yesterday.month == local.month && yesterday.year == local.year) {
      return AppStrings.recent.yesterday;
    }

    if (diff.inDays < 7) {
      return '${diff.inDays} ${AppStrings.recent.daysAgoSuffix}';
    }

    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')} ${_formatTime(local)}';
  }

  String _formatTime(DateTime value) {
    final hours = value.hour.toString().padLeft(2, '0');
    final minutes = value.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  @override
  Widget build(BuildContext context) {
    // Используем геттеры, которые мы добавили в контроллер на предыдущем шаге
    final stats = widget.controller.stats;
    final failOpen = stats.failOpenActive;
    final isActive = stats.vpnActive;
    final modeLabel = _modeLabel(stats.mode);
    final modeSummary = () {
      switch (stats.mode) {
        case ProtectionMode.ultra:
          return AppStrings.modes.ultraSummary;
        case ProtectionMode.advanced:
          return AppStrings.modes.strictSummary;
        case ProtectionMode.standard:
        default:
          return AppStrings.modes.standardSummary;
      }
    }();
    final showUltraWarning = isActive && stats.mode == ProtectionMode.ultra;

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.stats.headerTitle),
      ),
      body: RefreshIndicator(
        onRefresh: () async => widget.controller.refreshStats(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              // surfaceVariant может быть устаревшим в новых версиях Flutter,
              // используем secondaryContainer как безопасную альтернативу, если surfaceVariant недоступен
              color: colorScheme.secondaryContainer,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isActive
                              ? Icons.shield_rounded
                              : Icons.shield_outlined,
                          color: isActive
                              ? Colors.green
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isActive
                              ? AppStrings.stats.protectionActive
                              : AppStrings.stats.protectionInactive,
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (isActive) ...[
                      Text(
                        AppStrings.modes.modeStatus.replaceFirst('%s', modeLabel),
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        modeSummary,
                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSecondaryContainer),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        failOpen
                            ? AppStrings.stats.filterTemporarilyDisabled
                            : AppStrings.stats.filterActive,
                        style: TextStyle(
                          color: failOpen ? Colors.orangeAccent : Colors.green,
                          fontSize: 13,
                        ),
                      ),
                    ] else ...[
                      Text(
                        AppStrings.stats.filterInactiveDescription,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (showUltraWarning) ...[
              const SizedBox(height: 12),
              _StrictModeBanner(
                message: AppStrings.modes.ultraModeWarning,
              ),
            ],
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${AppStrings.stats.blockedTotal}: ${stats.totalBlocked}',
                        style: textTheme.bodyLarge),
                    const SizedBox(height: 4),
                    Text('${AppStrings.stats.blockedSession}: ${stats.sessionBlocked}',
                        style: textTheme.bodyLarge),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.recent.lastBlocked,
                  style: textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: stats.recentDomains.isEmpty ? null : () => _showRecent(context, stats.recentDomains),
                  child: Text(AppStrings.stats.showAll),
                )
              ],
            ),
            const SizedBox(height: 8),
            if (stats.recentDomains.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    AppStrings.recent.empty,
                    style: textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: stats.recentDomains.map((entry) {
                  // ИСПРАВЛЕНИЕ: entry - это объект BlockedEntry.
                  // Нам нужно достать из него поле .domain
                  return ListTile(
                    leading: const Icon(Icons.public, size: 20),
                    title: Text(entry.domain),
                    subtitle: Text(_formatTimestamp(entry.timestamp)),
                    dense: true,
                  );
                }).toList(),
              ),
          ],
        ),
      ),
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
}

class _StrictModeBanner extends StatelessWidget {
  const _StrictModeBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
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
              message,
              style: textTheme.bodySmall
                  ?.copyWith(color: Colors.amber.shade800, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
