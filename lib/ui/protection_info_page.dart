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
        title: const Text(AppStrings.infoTitle),
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
                      ? AppStrings.ultraModeActiveBanner
                      : AppStrings.strictModeActiveBanner),
              const SizedBox(height: 12),
            ],
            Text(AppStrings.infoIntro, style: bodyStyle),
            const SizedBox(height: 12),
            Text(AppStrings.infoBlocklist, style: bodyStyle),
            const SizedBox(height: 12),
            Text(AppStrings.infoModeStandard, style: bodyStyle),
            const SizedBox(height: 8),
            Text(AppStrings.infoModeStrict, style: bodyStyle),
            const SizedBox(height: 8),
            Text(AppStrings.infoModeUltra, style: bodyStyle),
            const SizedBox(height: 12),
            Text(AppStrings.infoPrivacy, style: bodyStyle),
            const SizedBox(height: 12),
            Text(AppStrings.infoControl, style: bodyStyle),
            const SizedBox(height: 24),
            Text(
              AppStrings.infoChecklistTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _InfoSection(
              title: AppStrings.infoHardwareTitle,
              items: const [
                AppStrings.infoHardware1,
                AppStrings.infoHardware2,
                AppStrings.infoHardware3,
              ],
            ),
            _InfoSection(
              title: AppStrings.infoNetworkTitle,
              items: const [
                AppStrings.infoNetwork1,
                AppStrings.infoNetwork2,
                AppStrings.infoNetwork3,
              ],
            ),
            _InfoSection(
              title: AppStrings.infoPermissionsTitle,
              items: const [
                AppStrings.infoPermissions1,
                AppStrings.infoPermissions2,
                AppStrings.infoPermissions3,
              ],
            ),
            _InfoSection(
              title: AppStrings.infoUxTitle,
              items: const [
                AppStrings.infoUx1,
                AppStrings.infoUx2,
                AppStrings.infoUx3,
              ],
            ),
            _InfoSection(
              title: AppStrings.infoSupplyTitle,
              items: const [
                AppStrings.infoSupply1,
                AppStrings.infoSupply2,
                AppStrings.infoSupply3,
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
