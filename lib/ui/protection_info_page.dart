import 'package:flutter/material.dart';

import 'strings.dart';

class ProtectionInfoPage extends StatelessWidget {
  const ProtectionInfoPage({super.key});

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
            Text(AppStrings.infoIntro, style: bodyStyle),
            const SizedBox(height: 12),
            Text(AppStrings.infoBlocklist, style: bodyStyle),
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
