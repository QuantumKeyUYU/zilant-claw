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

  @override
  Widget build(BuildContext context) {
    final stats = widget.controller.stats;
    final protectionOn = widget.controller.protectionEnabled;
    final modes = _activeModes();
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
            Container(
              decoration: BoxDecoration(
                color: protectionOn ? colorScheme.primaryContainer : colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    protectionOn ? AppStrings.stats.protectionActive : AppStrings.stats.protectionInactive,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: protectionOn ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    modes.isEmpty
                        ? AppStrings.stats.modesNone
                        : AppStrings.stats.modesActive.replaceFirst('%s', modes.join(', ')),
                    style: textTheme.bodyMedium?.copyWith(
                      color: protectionOn ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    protectionOn
                        ? AppStrings.stats.protectionSubtitleOn
                        : AppStrings.stats.protectionSubtitleOff,
                    style: textTheme.bodySmall?.copyWith(
                      color: protectionOn
                          ? colorScheme.onPrimaryContainer.withOpacity(0.9)
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (stats.failOpenActive) ...[
                    const SizedBox(height: 6),
                    Text(
                      AppStrings.home.protectionFailOpenWarning,
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.amber.shade800,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant
                    .withOpacity(colorScheme.brightness == Brightness.dark ? 0.6 : 1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.stats.statsSectionTitle,
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  _StatRow(
                    label: AppStrings.stats.statsTotal,
                    value: stats.totalRequestsToday.toString(),
                  ),
                  const SizedBox(height: 6),
                  _StatRow(
                    label: AppStrings.stats.statsBlockedTotal,
                    value: stats.blockedTotalToday.toString(),
                  ),
                  const SizedBox(height: 6),
                  _StatRow(
                    label: AppStrings.stats.statsBlockedClean,
                    value: stats.blockedNsfwToday.toString(),
                  ),
                  const SizedBox(height: 6),
                  _StatRow(
                    label: AppStrings.stats.statsBlockedFocus,
                    value: stats.blockedFocusToday.toString(),
                  ),
                  const SizedBox(height: 6),
                  _StatRow(
                    label: AppStrings.stats.statsAttention,
                    value: stats.attentionAttempts.toString(),
                  ),
                  const SizedBox(height: 6),
                  _StatRow(
                    label: AppStrings.stats.statsTracking,
                    value: stats.trackingAttempts.toString(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.stats.statsRecentBlocked,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (stats.recentDomains.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    AppStrings.stats.statsRecentEmpty,
                    style: textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Column(
                children: stats.recentDomains.take(10).map((entry) {
                  final category = _mapCategory(entry.category);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.public, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.domain,
                            style: textTheme.bodyLarge,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            category,
                            style: textTheme.labelMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  String _mapCategory(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'clean':
        return AppStrings.stats.categoryClean;
      case 'time_waster':
      case 'focus':
        return AppStrings.stats.categoryFocus;
      case 'ads':
        return AppStrings.stats.categoryAds;
      case 'analytics':
      case 'telemetry':
      case 'trackers':
        return AppStrings.stats.categoryTelemetry;
      default:
        return '—';
    }
  }

  List<String> _activeModes() {
    final modes = <String>[];
    if (widget.controller.cleanEnabled) {
      modes.add(AppStrings.home.cleanTitle);
    }
    if (widget.controller.focusEnabled) {
      modes.add(AppStrings.home.focusTitle);
    }
    return modes;
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    if (value.isEmpty) {
      return Text(
        label,
        style: textTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
