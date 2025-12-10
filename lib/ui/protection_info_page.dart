import 'package:flutter/material.dart';

import '../logic/protection_controller.dart';
import 'strings.dart';

class ProtectionInfoPage extends StatelessWidget {
  const ProtectionInfoPage({super.key, required this.mode});

  final ProtectionMode mode;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.info.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            if (mode == ProtectionMode.advanced || mode == ProtectionMode.ultra) ...[
              _StrictModeBanner(
                  message: mode == ProtectionMode.ultra
                      ? AppStrings.modes.ultraModeWarning
                      : AppStrings.modes.strictModeWarning),
              const SizedBox(height: 12),
            ],
            Text(AppStrings.info.intro, style: bodyStyle),
            const SizedBox(height: 12),
            Text(AppStrings.info.blocklist, style: bodyStyle),
            const SizedBox(height: 12),
            Text(AppStrings.info.modeStandard, style: bodyStyle),
            const SizedBox(height: 8),
            Text(AppStrings.info.modeStrict, style: bodyStyle),
            const SizedBox(height: 8),
            Text(AppStrings.info.modeUltra, style: bodyStyle),
            const SizedBox(height: 12),
            Text(AppStrings.info.privacy, style: bodyStyle),
            const SizedBox(height: 12),
            Text(AppStrings.info.control, style: bodyStyle),
            const SizedBox(height: 24),
            Text(
              AppStrings.info.checklistTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _InfoSection(
              title: AppStrings.info.hardwareTitle,
              items: const [
                AppStrings.info.hardware1,
                AppStrings.info.hardware2,
                AppStrings.info.hardware3,
              ],
            ),
            _InfoSection(
              title: AppStrings.info.networkTitle,
              items: const [
                AppStrings.info.network1,
                AppStrings.info.network2,
                AppStrings.info.network3,
              ],
            ),
            _InfoSection(
              title: AppStrings.info.permissionsTitle,
              items: const [
                AppStrings.info.permissions1,
                AppStrings.info.permissions2,
                AppStrings.info.permissions3,
              ],
            ),
            _InfoSection(
              title: AppStrings.info.uxTitle,
              items: const [
                AppStrings.info.ux1,
                AppStrings.info.ux2,
                AppStrings.info.ux3,
              ],
            ),
            _InfoSection(
              title: AppStrings.info.supplyTitle,
              items: const [
                AppStrings.info.supply1,
                AppStrings.info.supply2,
                AppStrings.info.supply3,
              ],
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

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: Text(
                        item,
                        style: textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
