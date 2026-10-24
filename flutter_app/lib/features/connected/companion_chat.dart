import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/components/travel_panels.dart';

/// Uses the existing owned-conversation endpoints. Drafts stay in memory only.
class CompanionChat extends ConsumerStatefulWidget {
  const CompanionChat({super.key});
  @override
  ConsumerState<CompanionChat> createState() => _CompanionChatState();
}

class _CompanionChatState extends ConsumerState<CompanionChat> {
  final draft = TextEditingController();
  final scroll = ScrollController();
  final turns = <({String question, Json answer})>[];
  String? conversation;
  String? error;
  DateTime? retryAt;
  Timer? cooldown;
  bool busy = false;
  bool useContext = false;
  bool get khmer => Localizations.localeOf(context).languageCode == 'km';
  String text(String en, String km) => khmer ? km : en;
  int get remaining => retryAt == null
      ? 0
      : (retryAt!.difference(DateTime.now()).inMilliseconds / 1000)
            .ceil()
            .clamp(0, 604800);

  @override
  void dispose() {
    cooldown?.cancel();
    draft.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final question = draft.text.trim();
    if (busy || remaining > 0 || question.isEmpty) return;
    if (question.length > 8000) {
      setState(
        () => error = text(
          'Use at most 8,000 characters.',
          'សូមប្រើមិនលើស ៨០០០ តួអក្សរ។',
        ),
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      if (conversation == null) {
        final id = string(await repo.conversation(), 'id');
        if (id.isEmpty) throw const FormatException('Missing conversation');
        conversation = id;
      }
      final answer = object(
        await repo.message(conversation!, question, useContext: useContext),
      );
      if (string(answer, 'text').trim().isEmpty) {
        throw const FormatException('Empty answer');
      }
      if (!mounted) return;
      setState(() {
        turns.add((question: question, answer: answer));
        draft.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (failure) {
      if (!mounted) return;
      final api = failure is ApiFailure ? failure : null;
      setState(() {
        error = api?.offline == true
            ? text(
                'No connection. Your question is kept here. Reconnect and try again.',
                'គ្មានការតភ្ជាប់។ សំណួររបស់អ្នកនៅទីនេះ។ សូមភ្ជាប់ ហើយព្យាយាមម្ដងទៀត។',
              )
            : api?.status == 429
            ? text(
                'AI usage limit reached. Please wait before trying again.',
                'បានដល់កម្រិតប្រើប្រាស់ AI។ សូមរង់ចាំមុនព្យាយាមម្ដងទៀត។',
              )
            : text(
                'The companion could not answer. Your question is kept here; try again shortly.',
                'ដៃគូមិនអាចឆ្លើយបាន។ សំណួររបស់អ្នកនៅទីនេះ។ សូមព្យាយាមម្ដងទៀត។',
              );
        final seconds = api?.retryAfterSeconds;
        retryAt = seconds != null && seconds > 0
            ? DateTime.now().add(Duration(seconds: seconds.clamp(1, 604800)))
            : null;
      });
      cooldown?.cancel();
      if (retryAt != null) {
        cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() {});
          if (remaining == 0) timer.cancel();
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(text('Your travel companion', 'ដៃគូធ្វើដំណើររបស់អ្នក')),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(20),
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: useContext,
                  onChanged: busy
                      ? null
                      : (value) => setState(() => useContext = value),
                  title: Text(
                    text('Use conversation context', 'ប្រើបរិបទសន្ទនា'),
                  ),
                  subtitle: Text(
                    text(
                      'Share up to 12 previous messages in this chat with Google Gemini for follow-up answers. Avoid sensitive details.',
                      'ចែករំលែកសារមុនរហូតដល់ ១២ ក្នុងការសន្ទនានេះជាមួយ Google Gemini សម្រាប់ចម្លើយបន្ត។ ជៀសវាងព័ត៌មានរសើប។',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (turns.isEmpty) ...[
                  const Icon(Icons.travel_explore_rounded, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    text('Where shall we go?', 'តើយើងទៅណា?'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text(
                      'Ask about Cambodia, compare destinations, or plan your day. Suggestions need your review; nothing is booked or changed.',
                      'សួរអំពីកម្ពុជា ប្រៀបធៀបគោលដៅ ឬរៀបចំផែនការប្រចាំថ្ងៃ។ សូមពិនិត្យសំណើ។ គ្មានការកក់ ឬការផ្លាស់ប្តូរដោយស្វ័យប្រវត្តិទេ។',
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final suggestion in [
                    text(
                      'Plan two relaxed days in Siem Reap',
                      'រៀបចំដំណើរកម្សាន្តសម្រាកពីរថ្ងៃនៅសៀមរាប',
                    ),
                    text(
                      'What should I know before visiting a temple?',
                      'តើខ្ញុំគួរដឹងអ្វីខ្លះមុនទៅទស្សនាប្រាសាទ?',
                    ),
                    text(
                      'Compare Kampot and Kep for a weekend',
                      'ប្រៀបធៀបកំពត និងកែបសម្រាប់ចុងសប្ដាហ៍',
                    ),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: busy
                            ? null
                            : () => setState(() => draft.text = suggestion),
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: Text(suggestion),
                      ),
                    ),
                ],
                for (final turn in turns) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.only(top: 16, bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: SelectableText(turn.question),
                    ),
                  ),
                  CompanionAnswer(data: turn.answer),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: string(turn.answer, 'text')),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                text('Answer copied', 'បានចម្លងចម្លើយ'),
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: Text(text('Copy answer', 'ចម្លងចម្លើយ')),
                    ),
                  ),
                ],
                if (busy)
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            text(
                              'Your companion is thinking…',
                              'ដៃគូរបស់អ្នកកំពុងគិត…',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '$error${remaining > 0 ? '\n${text('Try again in', 'ព្យាយាមម្ដងទៀតក្នុង')} ${remaining}s' : ''}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: draft,
                    onChanged: (_) => setState(() {}),
                    enabled: !busy,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 8000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: text('Ask your companion', 'សួរដៃគូរបស់អ្នក'),
                      counterText: '',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 52,
                  height: 52,
                  child: IconButton.filled(
                    tooltip: text('Send question', 'ផ្ញើសំណួរ'),
                    onPressed:
                        busy || remaining > 0 || draft.text.trim().isEmpty
                        ? null
                        : send,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
