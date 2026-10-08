import 'package:flutter/material.dart';
import '../../app/localization/strings.dart';
import '../../shared/components/components.dart';
import '../../shared/models/travel.dart';

Future<void> showConflict(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.t('conflict'), style: Theme.of(c).textTheme.headlineMedium),
            const SizedBox(height: 16),
            Text(c.t('conflictBody')),
            const SizedBox(height: 16),
            ActivityRow(const Activity(place: 'angkor', day: 0, time: '05:30')),
            ActivityRow(const Activity(place: 'angkor', day: 0, time: '10:00')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(c, 'local'),
                child: Text(c.t('keepLocal')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(c, 'remote'),
                child: Text(c.t('keepRemote')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${context.t('conflictResolved')} · ${context.t(choice == 'local' ? 'keepLocal' : 'keepRemote')}',
        ),
      ),
    );
  }
}
