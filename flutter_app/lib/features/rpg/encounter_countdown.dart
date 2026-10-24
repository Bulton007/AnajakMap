import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/localization/strings.dart';

/// Absolute server expiry survives backgrounding; never grants rewards locally.
class EncounterCountdown extends StatefulWidget {
  const EncounterCountdown({super.key, required this.expiresAt});
  final String expiresAt;
  @override
  State<EncounterCountdown> createState() => _CountdownState();
}

class _CountdownState extends State<EncounterCountdown>
    with WidgetsBindingObserver {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  void start() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    timer?.cancel();
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      start();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final end = DateTime.tryParse(widget.expiresAt);
    final seconds = end == null ? 0 : end.difference(DateTime.now()).inSeconds;
    final label = seconds <= 0
        ? (context.isKhmer
              ? 'ការជួបនេះផុតកំណត់ហើយ។ ផ្ទុកឡើងវិញដើម្បីបន្ត។'
              : 'Encounter expired. Refresh before continuing.')
        : '${context.isKhmer ? 'នៅសល់' : 'Time remaining'}: ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Row(
      children: [
        const Icon(Icons.timer_outlined),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
      ],
    );
  }
}
