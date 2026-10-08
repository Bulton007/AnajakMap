import 'package:flutter/material.dart';
import '../../app/localization/strings.dart';
import '../../shared/components/components.dart';
import '../../shared/models/travel.dart';
import '../offline/conflict_preview.dart';
import 'profile.dart';

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t('gallery'))),
    body: PageBody(
      children: [
        const PreferencesControls(),
        Section(context.t('buttons')),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              onPressed: () => inform(
                context,
                context.t('confirm'),
                context.t('demoNotice'),
              ),
              child: Text(context.t('confirm')),
            ),
            OutlinedButton(onPressed: () {}, child: Text(context.t('edit'))),
            TextButton(onPressed: () {}, child: Text(context.t('cancel'))),
            FilledButton(onPressed: null, child: Text(context.t('disabled'))),
            IconButton.filled(
              tooltip: context.t('save'),
              onPressed: () {},
              icon: const Icon(Icons.bookmark_border),
            ),
          ],
        ),
        Section(context.t('preferences')),
        TextField(
          decoration: InputDecoration(
            labelText: context.t('search'),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: InputDecoration(
            labelText: context.t('amount'),
            errorText: context.t('invalidAmount'),
          ),
        ),
        Section(context.t('itinerary')),
        const ActivityRow(Activity(place: 'angkor', day: 0, time: '05:30')),
        ActionCard(
          icon: Icons.auto_awesome,
          title: context.t('aiTrust'),
          subtitle: context.t('aiTrustBody'),
          onTap: () =>
              inform(context, context.t('source'), context.t('sourceDetail')),
        ),
        Section(context.t('feedback')),
        Notice(context.t('offlineBanner'), icon: Icons.cloud_off_outlined),
        const SizedBox(height: 12),
        Notice(context.t('error'), icon: Icons.error_outline, error: true),
        const SizedBox(height: 12),
        Pill(context.t('pending'), icon: Icons.sync),
        const SizedBox(height: 16),
        Semantics(
          label: context.t('loading'),
          child: const LinearProgressIndicator(),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => showConflict(context),
          child: Text(context.t('conflictPreview')),
        ),
        EmptyState(
          title: context.t('empty'),
          body: context.t('emptyTripsBody'),
          action: FilledButton(
            onPressed: () {},
            child: Text(context.t('retry')),
          ),
        ),
      ],
    ),
  );
}
