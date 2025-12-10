import 'package:flutter/material.dart';
// Убедись, что путь к контроллеру верный
import '../logic/protection_controller.dart';
import 'strings.dart';

// Мы определяем класс Strings прямо здесь, чтобы избежать ошибки импорта.
// Если у тебя есть файл strings.dart, проверь, что класс в нем называется именно 'Strings'.
class Strings {
  static const String vpnActive = 'Защита активна';
  static const String vpnInactive = 'Защита отключена';
  static const String protectionMode = 'Режим';
  static const String filterTemporarilyDisabled = 'Фильтрация временно отключена';
  static const String filterActive = 'Фильтрация работает';
  static const String blockedTotal = 'Всего заблокировано';
  static const String blockedSession = 'За сессию';
  static const String recentBlockedDomains = 'Последние заблокированные';
}

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
    // Используем геттеры, которые мы добавили в контроллер на предыдущем шаге
    final stats = widget.controller.stats;
    final failOpen = stats.failOpenActive;
    final vpnActive = stats.vpnActive;
    final mode = stats.modeName;
    final isStrict =
        stats.mode == ProtectionMode.advanced || stats.mode == ProtectionMode.ultra;

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика и домены'),
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
                          vpnActive
                              ? Icons.shield_rounded
                              : Icons.shield_outlined,
                          color: vpnActive
                              ? Colors.green
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          vpnActive
                              ? Strings.vpnActive
                              : Strings.vpnInactive,
                          style: textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${Strings.protectionMode}: $mode',
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      failOpen
                          ? Strings.filterTemporarilyDisabled
                          : Strings.filterActive,
                      style: TextStyle(
                        color:
                            failOpen ? Colors.orangeAccent : Colors.greenAccent,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isStrict) ...[
              const SizedBox(height: 12),
              _StrictModeBanner(
                message: stats.mode == ProtectionMode.ultra
                    ? AppStrings.ultraModeActiveBanner
                    : AppStrings.strictModeActiveBanner,
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
                    Text(
                      '${Strings.blockedTotal}: ${stats.totalBlocked}',
                      style: textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${Strings.blockedSession}: ${stats.sessionBlocked}',
                      style: textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              Strings.recentBlockedDomains,
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (stats.recentDomains.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Пока ничего не заблокировано — вы в чистом интернете 😌',
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
                    // Можно добавить время блокировки, если нужно:
                    // subtitle: Text(entry.timestamp.toString()), 
                    dense: true,
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
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
