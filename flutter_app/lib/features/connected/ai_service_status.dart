import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';

/// Describes server configuration, never claims that a model request succeeded.
class AiServiceStatus extends ConsumerWidget {
  const AiServiceStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(guideCapabilitiesProvider);
    final data = state.asData?.value;
    String label(String en, String km) => context.isKhmer ? km : en;
    final demo = data?['demo'] == true;
    final missing = data?['configured'] == false && !demo;
    final failure = state.asError?.error;
    final expired =
        failure is ApiFailure &&
        (failure.status == 401 || failure.status == 403);
    final title = state.isLoading
        ? label('Checking AI connection…', 'កំពុងពិនិត្យការតភ្ជាប់ AI…')
        : state.hasError
        ? label('Could not check AI', 'មិនអាចពិនិត្យ AI បាន')
        : demo
        ? label('Demo companion', 'ដៃគូសាកល្បង')
        : missing
        ? label('AI setup needed on your server', 'ត្រូវរៀបចំ AI លើម៉ាស៊ីនមេ')
        : label(
            'AI assistance · you stay in control',
            'ជំនួយ AI · អ្នកជាអ្នកសម្រេច',
          );
    final subtitle = state.hasError
        ? expired
              ? label(
                  'Sign in again to check the connection.',
                  'សូមចូលម្ដងទៀតដើម្បីពិនិត្យការតភ្ជាប់។',
                )
              : label(
                  'Check your connection, then retry.',
                  'សូមពិនិត្យការតភ្ជាប់ ហើយព្យាយាមម្ដងទៀត។',
                )
        : demo
        ? label(
            'Sample answers, not live AI.',
            'ចម្លើយគំរូ មិនមែន AI ផ្ទាល់ទេ។',
          )
        : missing
        ? label(
            'Manual trip planning is available.',
            'អ្នកអាចរៀបចំដំណើរដោយខ្លួនឯងបាន។',
          )
        : label('Review suggestions before saving.', 'ពិនិត្យសំណើមុនរក្សាទុក។');
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: state.hasError || missing
          ? colors.errorContainer
          : colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  state.hasError || missing
                      ? Icons.cloud_off_rounded
                      : Icons.auto_awesome_rounded,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (state.isLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ] else if (state.hasError || missing || demo)
              TextButton.icon(
                onPressed: () => ref.invalidate(guideCapabilitiesProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(label('Check again', 'ពិនិត្យម្ដងទៀត')),
              ),
          ],
        ),
      ),
    );
  }
}
