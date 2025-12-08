import 'package:flutter/material.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';
import 'logic/protection_controller.dart';
import 'ui/strings.dart';

void main() {
  runApp(const DigitalDefenderApp());
}

class DigitalDefenderApp extends StatefulWidget {
  const DigitalDefenderApp({super.key});

  @override
  State<DigitalDefenderApp> createState() => _DigitalDefenderAppState();
}

class _DigitalDefenderAppState extends State<DigitalDefenderApp> {
  final ProtectionController _controller = ProtectionController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.title,
      theme: buildTheme(),
      home: HomePage(controller: _controller),
    );
  }
}
