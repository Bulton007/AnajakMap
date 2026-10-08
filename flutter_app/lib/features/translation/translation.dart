import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/localization/strings.dart';
import '../../core/storage/app_state.dart';
import '../../shared/components/components.dart';

class TranslationScreen extends ConsumerWidget {
  const TranslationScreen({super.key});
  static const phrases = {
    'hello': ('Hello', 'សួស្តី'),
    'thanks': ('Thank you', 'អរគុណ'),
    'water': ('Water, please', 'សុំទឹកមួយ'),
    'howMuch': ('How much is this?', 'តើនេះថ្លៃប៉ុន្មាន?'),
  };
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(appStateProvider).phrases;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('translation'))),
      body: PageBody(
        children: [
          Notice(context.t('translationNotice'), icon: Icons.translate),
          const SizedBox(height: 22),
          for (final p in phrases.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.value.$1,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              p.value.$2,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: context.t('save'),
                        onPressed: saved.contains(p.key)
                            ? null
                            : () => persist(
                                context,
                                () => ref
                                    .read(appStateProvider.notifier)
                                    .savePhrase(p.key),
                              ),
                        icon: Icon(
                          saved.contains(p.key)
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => inform(
              context,
              context.t('camera'),
              context.t('translationNotice'),
            ),
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(context.t('camera')),
          ),
          Section(context.t('savedPhrases')),
          Text(
            saved.isEmpty
                ? context.t('empty')
                : saved.map((e) => context.t(e)).join(' · '),
          ),
        ],
      ),
    );
  }
}
