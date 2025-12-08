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
          ],
        ),
      ),
    );
  }
}
