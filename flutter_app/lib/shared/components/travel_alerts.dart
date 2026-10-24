import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../formatting/travel_dates.dart';

class EmergencyContactCard extends StatefulWidget {
  const EmergencyContactCard({
    super.key,
    required this.contact,
    this.openDialer,
  });
  final Json contact;
  final Future<bool> Function(Uri)? openDialer;
  @override
  State<EmergencyContactCard> createState() => _EmergencyContactCardState();
}

class _EmergencyContactCardState extends State<EmergencyContactCard> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final phone = string(widget.contact, 'phone'),
        normalized = phone.replaceAll(RegExp(r'[ ()-]'), '');
    final valid = RegExp(r'^\+?\d{3,20}$').hasMatch(normalized);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.contact_emergency_outlined),
            const SizedBox(height: 12),
            Text(
              string(widget.contact, 'label'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SelectableText(phone),
            const SizedBox(height: 8),
            Text(
              context.isKhmer
                  ? 'បើកកម្មវិធីហៅទូរសព្ទរបស់ឧបករណ៍។ មិនហៅដោយស្វ័យប្រវត្តិទេ។'
                  : 'Opens your device dialer. No call is placed automatically.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: !valid || busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      var opened = false;
                      try {
                        final uri = Uri(scheme: 'tel', path: normalized);
                        opened = widget.openDialer != null
                            ? await widget.openDialer!(uri)
                            : await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                      } catch (_) {}
                      if (!context.mounted) return;
                      setState(() => busy = false);
                      if (!opened) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              context.isKhmer
                                  ? 'មិនអាចបើកកម្មវិធីហៅទូរសព្ទបានទេ។ សូមប្រើលេខខាងលើ។'
                                  : 'Could not open the dialer. Use the number above.',
                            ),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.dialpad),
              label: Text(
                context.isKhmer ? 'បើកកម្មវិធីហៅទូរសព្ទ' : 'Open dialer',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TravelNotificationCard extends StatelessWidget {
  const TravelNotificationCard({super.key, required this.delivery});
  final Json delivery;
  @override
  Widget build(BuildContext context) {
    final status = string(delivery, 'status');
    final sample = status == 'MOCK_DELIVERED';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              sample
                  ? Icons.science_outlined
                  : status == 'DEAD'
                  ? Icons.error_outline
                  : Icons.notifications_outlined,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    string(delivery, 'title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    travelDateTime(
                      string(delivery, 'dueAt'),
                      locale: context.isKhmer ? 'km' : 'en',
                    ),
                  ),
                  Text(
                    sample
                        ? (context.isKhmer
                              ? 'ការសាកល្បង · គ្មានការជូនដំណឹងទៅឧបករណ៍'
                              : 'Simulation · no device notification sent')
                        : status,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
