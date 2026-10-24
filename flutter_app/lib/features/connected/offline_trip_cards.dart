import 'package:flutter/material.dart';
import '../../shared/formatting/travel_money.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/components/travel_panels.dart';
import '../../shared/formatting/travel_dates.dart';

class DownloadedTripCard extends StatelessWidget {
  const DownloadedTripCard({
    super.key,
    required this.snapshot,
    required this.onOpen,
    required this.onEdit,
    required this.onExpense,
    required this.onJournal,
  });
  final Json snapshot;
  final VoidCallback onOpen, onEdit, onExpense, onJournal;
  @override
  Widget build(BuildContext context) {
    final data = object(snapshot['data']), trip = object(data['trip']);
    final zone = string(trip, 'timezone', 'Asia/Phnom_Penh');
    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(Icons.offline_pin_outlined)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        string(trip, 'title'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(string(trip, 'destination')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            IconFact(
              Icons.calendar_today_outlined,
              travelDateRange(
                string(trip, 'startDate'),
                string(trip, 'endDate'),
                locale: context.isKhmer ? 'km' : 'en',
              ),
            ),
            IconFact(
              Icons.download_done_rounded,
              '${context.t('savedAt')} · ${travelDateTime(string(snapshot, 'savedAt'), zone: zone, locale: context.isKhmer ? 'km' : 'en')}',
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: onOpen,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(context.t('openDownload')),
            ),
            const Divider(height: 28),
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_calendar_outlined),
              label: Text(context.t('queueEdit')),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: onExpense,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(context.t('addExpense')),
                ),
                TextButton.icon(
                  onPressed: onJournal,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(context.t('newEntry')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class OfflineSnapshotView extends StatelessWidget {
  const OfflineSnapshotView({super.key, required this.data});
  final Json data;
  @override
  Widget build(BuildContext context) {
    final trip = object(data['trip']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TravelHero(
          title: string(trip, 'title'),
          subtitle: string(trip, 'destination'),
          icon: Icons.offline_pin_outlined,
        ),
        Notice(context.t('cachedRead'), icon: Icons.wifi_off_rounded),
        CalendarPanel(
          data: object(data['calendar']),
          zone: string(trip, 'timezone', 'Asia/Phnom_Penh'),
        ),
        Section(context.t('contacts')),
        if (objects(data['contacts']).isEmpty)
          VisualEmpty(
            icon: Icons.contact_phone_outlined,
            title: context.t('empty'),
          ),
        for (final contact in objects(data['contacts']))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: IconFact(
                Icons.phone_outlined,
                '${string(contact, 'label')}\n${string(contact, 'phone')}',
              ),
            ),
          ),
        // Map points remain part of the download, with human-readable names.
        Section(context.t('map')),
        if (objects(data['map']).isEmpty)
          VisualEmpty(icon: Icons.map_outlined, title: context.t('empty')),
        for (final point in objects(data['map']))
          IconFact(Icons.place_outlined, string(point, 'title')),
      ],
    );
  }
}

class PendingChangePreview extends StatelessWidget {
  const PendingChangePreview({super.key, required this.operation});
  final Json operation;
  @override
  Widget build(BuildContext context) {
    final kind = string(operation, 'kind'), body = object(operation['body']);
    final trip = object(body['trip']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconFact(
          kind == 'expense'
              ? Icons.receipt_long_outlined
              : kind == 'journal'
              ? Icons.edit_note
              : Icons.edit_calendar_outlined,
          context.t(
            kind == 'expense'
                ? 'addExpense'
                : kind == 'journal'
                ? 'newEntry'
                : 'editTrip',
          ),
        ),
        if (kind == 'trip') ...[
          Text(
            string(trip, 'title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          IconFact(Icons.place_outlined, string(trip, 'destination')),
          IconFact(
            Icons.calendar_today_outlined,
            travelDateRange(
              string(trip, 'startDate'),
              string(trip, 'endDate'),
              locale: context.isKhmer ? 'km' : 'en',
            ),
          ),
        ] else ...[
          Text(
            string(body, kind == 'expense' ? 'description' : 'title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (kind == 'expense')
            IconFact(
              Icons.payments_outlined,
              travelMoney(
                body['amount'],
                string(body, 'currency'),
                locale: context.isKhmer ? 'km' : 'en',
              ),
            ),
          if (kind == 'journal') Text(string(body, 'content')),
        ],
        const SizedBox(height: 10),
        IconFact(
          string(operation, 'state') == 'conflict'
              ? Icons.sync_problem
              : Icons.cloud_upload_outlined,
          context.t(
            string(operation, 'state') == 'conflict'
                ? 'conflictTitle'
                : 'queued',
          ),
        ),
      ],
    );
  }
}
