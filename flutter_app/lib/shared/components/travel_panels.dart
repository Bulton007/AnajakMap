import 'package:flutter/material.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../formatting/travel_dates.dart';
import 'components.dart';

/// Bundled Cambodia photography is decorative; it is not a photo of each stop.
class TravelHero extends StatelessWidget {
  const TravelHero({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.explore_outlined,
  });
  final String title, subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: SizedBox(
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/angkor.jpg',
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
            Positioned.fill(
              child: ColoredBox(color: Colors.black.withValues(alpha: .64)),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: Colors.white, size: 32),
                  const SizedBox(height: 28),
                  Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class IconFact extends StatelessWidget {
  const IconFact(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class VisualEmpty extends StatelessWidget {
  const VisualEmpty({super.key, required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(child: Text(title)),
        ],
      ),
    ),
  );
}

class ScheduleCard extends StatelessWidget {
  const ScheduleCard({
    super.key,
    required this.item,
    required this.zone,
    this.event = false,
  });
  final Json item;
  final String zone;
  final bool event;
  @override
  Widget build(BuildContext context) {
    final source = string(item, 'source');
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Icon(
                    event ? Icons.event_outlined : Icons.location_on_outlined,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    string(item, 'title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            IconFact(
              Icons.schedule_rounded,
              travelTimeRange(
                string(item, 'startsAt'),
                string(item, 'endsAt'),
                zone: zone,
                locale: context.isKhmer ? 'km' : 'en',
              ),
            ),
            if (source.isNotEmpty)
              ExpansionTile(
                key: PageStorageKey(
                  'schedule-source-${item['id'] ?? item['ID']}-${string(item, 'startsAt')}',
                ),
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: Text(context.t('source')),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(source),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class CalendarPanel extends StatelessWidget {
  const CalendarPanel({super.key, required this.data, required this.zone});
  final Json data;
  final String zone;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final section in ['events', 'activities']) ...[
        Section(context.t(section)),
        if (objects(data[section]).isEmpty)
          VisualEmpty(
            icon: section == 'events'
                ? Icons.event_available_outlined
                : Icons.route_outlined,
            title: context.t('empty'),
          ),
        for (final item in objects(data[section]))
          ScheduleCard(
            item: item,
            zone: string(item, 'timezone', zone),
            event: section == 'events',
          ),
      ],
    ],
  );
}

class GenerationStatusPanel extends StatelessWidget {
  const GenerationStatusPanel({
    super.key,
    required this.status,
    this.waiting = false,
    this.failureCode = '',
    this.retryAt = '',
  });
  final String status;
  final String failureCode, retryAt;
  final bool waiting;
  @override
  Widget build(BuildContext context) {
    final failed = status == 'FAILED', ready = status == 'SUCCEEDED';
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconFact(
              failed
                  ? Icons.error_outline
                  : ready
                  ? Icons.task_alt
                  : Icons.auto_awesome,
              context.t(
                failed
                    ? 'jobFailed'
                    : ready
                    ? 'proposalReady'
                    : waiting
                    ? 'planningJourney'
                    : 'requestPaused',
              ),
            ),
            if (failed) ...[
              const SizedBox(height: 12),
              Text(
                context.t(
                  failureCode == 'AI_RATE_LIMITED'
                      ? 'aiUsageLimit'
                      : failureCode == 'INVALID_AI_RESPONSE'
                      ? 'aiInvalidResponse'
                      : 'aiTemporarilyUnavailable',
                ),
              ),
              const SizedBox(height: 12),
              IconFact(Icons.shield_outlined, context.t('tripUnchanged')),
              if (failureCode == 'AI_RATE_LIMITED' &&
                  DateTime.tryParse(retryAt) != null)
                IconFact(
                  Icons.schedule,
                  '${context.t('retryAvailable')} · ${travelDateTime(retryAt, locale: context.isKhmer ? 'km' : 'en')}',
                ),
            ],
            if (waiting && !failed && !ready) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class CompanionAnswer extends StatelessWidget {
  const CompanionAnswer({super.key, required this.data});
  final Json data;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconFact(Icons.auto_awesome, context.t('ai')),
          const Divider(height: 28),
          SelectableText(string(data, 'translatedText', string(data, 'text'))),
          if (data['mock'] == true) ...[
            const SizedBox(height: 12),
            Text(context.t('mock')),
          ],
          if (string(data, 'source').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              string(data, 'source'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );
}
