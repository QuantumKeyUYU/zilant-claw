import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/protection_controller.dart';
import 'protection_info_page.dart';
import 'strings.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final ProtectionController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    widget.controller.refreshBlockedCount();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => widget.controller.refreshBlockedCount(),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onControllerChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final isOn = state == ProtectionState.on;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.title),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: AppStrings.infoTitle,
            onPressed: () => _openInfoPage(context),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            Expanded(child: Center(child: _buildDragon(isOn))),
            const SizedBox(height: 24),
            _buildToggle(context, state),
            const SizedBox(height: 16),
            _buildStatusText(state),
            const SizedBox(height: 12),
            _buildProgressText(state),
            if (state == ProtectionState.error &&
                widget.controller.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  widget.controller.errorMessage!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            const SizedBox(height: 24),
            _buildPoweredBy(context),
            const SizedBox(height: 8),
            _buildBlockedCount(context),
            const SizedBox(height: 8),
            _buildInfoButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildDragon(bool isOn) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      height: 240,
      width: 240,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: isOn
              ? const [Color(0xFF3DBE8B), Color(0xFF6EE7B7)]
              : const [Color(0xFF1F2A3E), Color(0xFF0E1525)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          if (isOn)
            BoxShadow(
              color: const Color(0xFF3DBE8B).withOpacity(0.4),
              blurRadius: 32,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
        ],
        border: Border.all(
          color: isOn ? const Color(0xFF8FF2C9) : Colors.white24,
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          '🐉',
          style: TextStyle(
            fontSize: 96,
            shadows: [
              if (isOn)
                const Shadow(
                  offset: Offset(0, 0),
                  blurRadius: 12,
                  color: Color(0xCC8FF2C9),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggle(BuildContext context, ProtectionState state) {
    final isBusy = state == ProtectionState.turningOn ||
        state == ProtectionState.turningOff;
    final isOn = state == ProtectionState.on;

    return GestureDetector(
      onTap: isBusy
          ? null
          : () async {
              await widget.controller.toggleProtection();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 120,
        width: 220,
        decoration: BoxDecoration(
          color: isOn ? const Color(0xFF3DBE8B) : const Color(0xFF1F2A3E),
          borderRadius: BorderRadius.circular(60),
          boxShadow: isOn
              ? [
                  BoxShadow(
                    color: const Color(0xFF3DBE8B).withOpacity(0.35),
                    blurRadius: 24,
                    spreadRadius: 1,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              left: isOn ? 110 : 10,
              top: 10,
              bottom: 10,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    isOn ? Icons.shield : Icons.shield_outlined,
                    color: isOn ? const Color(0xFF3DBE8B) : Colors.grey[600],
                    size: 36,
                  ),
                ),
              ),
            ),
            if (isBusy)
              const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 3,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusText(ProtectionState state) {
    String text;
    switch (state) {
      case ProtectionState.on:
        text = AppStrings.protectionOn;
        break;
      case ProtectionState.turningOn:
        text = AppStrings.protectionTurningOn;
        break;
      case ProtectionState.turningOff:
        text = AppStrings.protectionTurningOff;
        break;
      case ProtectionState.error:
        text = AppStrings.protectionError;
        break;
      case ProtectionState.off:
      default:
        text = AppStrings.protectionOff;
        break;
    }
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context)
          .textTheme
          .headlineSmall
          ?.copyWith(color: Colors.white),
    );
  }

  Widget _buildProgressText(ProtectionState state) {
    switch (state) {
      case ProtectionState.turningOn:
        return const Text(AppStrings.progressTurningOn);
      case ProtectionState.turningOff:
        return const Text(AppStrings.progressTurningOff);
      case ProtectionState.error:
        return const Text(AppStrings.progressError);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPoweredBy(BuildContext context) {
    return Text(
      AppStrings.poweredBy,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white.withOpacity(0.6),
          ),
    );
  }

  Widget _buildBlockedCount(BuildContext context) {
    final count = widget.controller.blockedCount;
    return Text(
      '${AppStrings.blockedRequestsLabel}$count',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white.withOpacity(0.65),
          ),
    );
  }

  Widget _buildInfoButton(BuildContext context) {
    return TextButton(
      onPressed: () => _openInfoPage(context),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white70,
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text(AppStrings.protectionInfoLink),
    );
  }

  void _openInfoPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProtectionInfoPage()),
    );
  }
}
