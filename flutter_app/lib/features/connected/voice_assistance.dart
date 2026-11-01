import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/media/voice_recorder.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/components/components.dart';
import '../../shared/components/travel_panels.dart';
import 'ai_service_status.dart';

enum _VoiceStage {
  idle,
  starting,
  recording,
  stopping,
  ready,
  sending,
  answered,
}

/// Recording permission only enables local capture. Provider sharing requires
/// separate consent followed by the user's explicit Send action.
class VoiceAssistanceScreen extends ConsumerStatefulWidget {
  const VoiceAssistanceScreen({super.key});

  @override
  ConsumerState<VoiceAssistanceScreen> createState() => _VoiceAssistanceState();
}

class _VoiceAssistanceState extends ConsumerState<VoiceAssistanceScreen>
    with WidgetsBindingObserver {
  late final VoiceRecorder recorder;
  final clock = Stopwatch();
  Timer? ticker;
  Timer? cooldown;
  _VoiceStage stage = _VoiceStage.idle;
  VoiceRecording? recording;
  Json? answer;
  String? error;
  String? mediaId;
  bool consent = false;
  Duration elapsed = Duration.zero;
  DateTime? retryAt;
  CancelToken? cancel;
  int epoch = 0;

  bool get khmer => Localizations.localeOf(context).languageCode == 'km';
  String text(String en, String km) => khmer ? km : en;
  bool get capturing => stage == _VoiceStage.recording;
  bool get busy =>
      stage == _VoiceStage.starting ||
      stage == _VoiceStage.stopping ||
      stage == _VoiceStage.sending;
  int get retrySeconds => retryAt == null
      ? 0
      : (retryAt!.difference(DateTime.now()).inMilliseconds / 1000)
            .ceil()
            .clamp(0, 604800);

  @override
  void initState() {
    super.initState();
    recorder = ref.read(voiceRecorderProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    ++epoch;
    WidgetsBinding.instance.removeObserver(this);
    ticker?.cancel();
    cooldown?.cancel();
    clock.stop();
    cancel?.cancel();
    recording = null;
    unawaited(recorder.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The native permission dialog temporarily removes window focus. Waiting
    // for that dialog is not background recording; hidden/paused still cancel.
    if (state == AppLifecycleState.inactive && stage == _VoiceStage.starting) {
      return;
    }
    if (state != AppLifecycleState.resumed &&
        (capturing ||
            stage == _VoiceStage.starting ||
            stage == _VoiceStage.stopping)) {
      ++epoch;
      ticker?.cancel();
      clock.stop();
      unawaited(recorder.cancel());
      setState(() {
        stage = _VoiceStage.idle;
        recording = null;
        consent = false;
        error = text(
          'Recording stopped when the app left the foreground. Record again when ready.',
          'ការថតបានបញ្ឈប់ពេលចាកចេញពីកម្មវិធី។ សូមថតម្ដងទៀតពេលរួចរាល់។',
        );
      });
    }
  }

  Future<void> start() async {
    if (busy || capturing) return;
    final operation = ++epoch;
    setState(() {
      stage = _VoiceStage.starting;
      error = null;
      answer = null;
      recording = null;
      mediaId = null;
      consent = false;
      elapsed = Duration.zero;
    });
    try {
      await recorder.start();
      if (!mounted || operation != epoch) return;
      clock.reset();
      clock.start();
      setState(() => stage = _VoiceStage.recording);
      ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted || !capturing) return;
        setState(() => elapsed = clock.elapsed);
        if (elapsed >= voiceMaxDuration) unawaited(stop());
      });
    } catch (failure) {
      if (!mounted || operation != epoch) return;
      setState(() {
        stage = _VoiceStage.idle;
        error = failure is VoiceRecorderFailure && failure.code == 'PERMISSION'
            ? text(
                'Microphone permission was denied. Enable it in your device settings to record.',
                'មិនបានអនុញ្ញាតមីក្រូហ្វូន។ សូមអនុញ្ញាតក្នុងការកំណត់ឧបករណ៍ដើម្បីថត។',
              )
            : text(
                'Recording could not start. Check microphone access and try again.',
                'មិនអាចចាប់ផ្ដើមថតបាន។ សូមពិនិត្យមីក្រូហ្វូន ហើយព្យាយាមម្ដងទៀត។',
              );
      });
    }
  }

  Future<void> stop() async {
    if (!capturing) return;
    final operation = epoch;
    ticker?.cancel();
    clock.stop();
    setState(() => stage = _VoiceStage.stopping);
    try {
      final clip = await recorder.stop();
      if (clip.bytes.isEmpty ||
          clip.bytes.length > voiceMaxBytes ||
          clip.duration > voiceMaxDuration) {
        throw const VoiceRecorderFailure('SIZE');
      }
      if (!mounted || operation != epoch) return;
      setState(() {
        recording = clip;
        elapsed = clip.duration;
        stage = _VoiceStage.ready;
      });
    } catch (_) {
      if (!mounted || operation != epoch) return;
      setState(() {
        stage = _VoiceStage.idle;
        error = text(
          'No usable recording was saved. Keep it under 60 seconds and try again.',
          'មិនមានការថតដែលអាចប្រើបាន។ សូមថតក្រោម ៦០ វិនាទី ហើយព្យាយាមម្ដងទៀត។',
        );
      });
    }
  }

  Future<void> send() async {
    final clip = recording;
    final configured = ref
        .read(guideCapabilitiesProvider)
        .asData
        ?.value['voice'];
    if (busy ||
        capturing ||
        !consent ||
        clip == null ||
        retrySeconds > 0 ||
        configured != true) {
      return;
    }
    final operation = epoch;
    setState(() {
      stage = _VoiceStage.sending;
      error = null;
      cancel = CancelToken();
    });
    try {
      final api = ref.read(apiProvider);
      if (mediaId == null) {
        final uploaded = object(
          await api.request(
            'POST',
            'guide/media',
            body: FormData.fromMap({
              'file': MultipartFile.fromBytes(
                clip.bytes,
                filename: 'voice.wav',
                contentType: DioMediaType.parse('audio/wav'),
              ),
            }),
            cancel: cancel,
          ),
        );
        final id = string(uploaded, 'mediaId');
        if (id.isEmpty) throw const FormatException('Missing audio identifier');
        mediaId = id;
      }
      if (!mounted || operation != epoch) return;
      final result = object(
        await api.request(
          'POST',
          'guide/voice',
          body: {
            'input': {
              'mediaId': mediaId,
              'shareWithProvider': true,
              'language': khmer ? 'km' : 'en',
            },
          },
          cancel: cancel,
        ),
      );
      if (string(result, 'transcript').trim().isEmpty ||
          string(result, 'text').trim().isEmpty ||
          result['mock'] != false) {
        throw const FormatException('Missing confirmed voice response');
      }
      if (!mounted || operation != epoch) return;
      setState(() {
        answer = result;
        stage = _VoiceStage.answered;
        recording = null;
        consent = false;
      });
    } catch (failure) {
      if (!mounted || operation != epoch) return;
      final api = failure is ApiFailure ? failure : null;
      setState(() {
        stage = _VoiceStage.ready;
        error = api?.offline == true
            ? text(
                'No connection. Your recording is kept on this screen. Reconnect, then send again.',
                'គ្មានការតភ្ជាប់។ ការថតនៅក្នុងអេក្រង់នេះ។ សូមភ្ជាប់ ហើយផ្ញើម្ដងទៀត។',
              )
            : api?.status == 429
            ? text(
                'AI usage limit reached. Wait before trying again.',
                'បានដល់កម្រិតប្រើប្រាស់ AI។ សូមរង់ចាំមុនព្យាយាមម្ដងទៀត។',
              )
            : text(
                'The companion could not process this recording. Try again, or record a clearer question.',
                'ដៃគូមិនអាចដំណើរការការថតនេះបាន។ សូមព្យាយាមម្ដងទៀត ឬថតសំណួរឲ្យច្បាស់ជាងមុន។',
              );
        final seconds = api?.retryAfterSeconds;
        retryAt = seconds != null && seconds > 0
            ? DateTime.now().add(Duration(seconds: seconds.clamp(1, 604800)))
            : null;
      });
      cooldown?.cancel();
      if (retryAt != null) {
        cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) return timer.cancel();
          setState(() {});
          if (retrySeconds == 0) timer.cancel();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(voiceRecorderProvider);
    final capability = ref.watch(guideCapabilitiesProvider);
    final available = capability.asData?.value['voice'] == true;
    final seconds = elapsed.inSeconds.clamp(0, 60);
    final time =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: Text(text('Voice assistance', 'ជំនួយសំឡេង'))),
      body: SafeArea(
        child: PageBody(
          children: [
            TravelHero(
              title: text('Ask with your voice', 'សួរដោយសំឡេងរបស់អ្នក'),
              subtitle: text(
                'Record a travel question, then choose whether to share it with your companion.',
                'ថតសំណួរធ្វើដំណើរ បន្ទាប់មកជ្រើសរើសចែករំលែកជាមួយដៃគូរបស់អ្នក។',
              ),
              icon: Icons.mic_rounded,
            ),
            const AiServiceStatus(),
            const SizedBox(height: 16),
            if (capability.hasValue && !available) ...[
              Notice(
                text(
                  'Voice assistance is unavailable on this server. No recording will be uploaded.',
                  'ជំនួយសំឡេងមិនទាន់មានលើម៉ាស៊ីនមេនេះ។ មិនមានការថតត្រូវផ្ទុកឡើងទេ។',
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      capturing ? Icons.graphic_eq : Icons.mic_none_rounded,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: capturing,
                      child: Text(
                        '$time / 1:00',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      recording != null
                          ? text(
                              'Recording ready · stored only in memory',
                              'ការថតរួចរាល់ · រក្សាទុកតែក្នុងអង្គចងចាំ',
                            )
                          : capturing
                          ? text('Recording…', 'កំពុងថត…')
                          : text(
                              'Up to 60 seconds · maximum 4 MB',
                              'រហូតដល់ ៦០ វិនាទី · អតិបរមា ៤ MB',
                            ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const Key('voice-record'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: capturing
                          ? stop
                          : busy || !available
                          ? null
                          : start,
                      icon: Icon(
                        capturing ? Icons.stop_rounded : Icons.mic_rounded,
                      ),
                      label: Text(
                        capturing
                            ? text('Stop recording', 'បញ្ឈប់ការថត')
                            : recording != null || answer != null
                            ? text('Record again', 'ថតម្ដងទៀត')
                            : text('Record question', 'ថតសំណួរ'),
                      ),
                    ),
                    if (busy) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
            if (recording != null) ...[
              const SizedBox(height: 16),
              CheckboxListTile(
                key: const Key('voice-consent'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: consent,
                onChanged: busy
                    ? null
                    : (value) => setState(() => consent = value == true),
                title: Text(
                  text(
                    'I agree to send this recording to the backend and Google Gemini.',
                    'ខ្ញុំយល់ព្រមផ្ញើការថតនេះទៅម៉ាស៊ីនមេ និង Google Gemini។',
                  ),
                ),
                subtitle: Text(
                  text(
                    'Avoid names and private information. Audio is uploaded only when you tap Send. AI transcription and answers can be wrong.',
                    'ជៀសវាងឈ្មោះ និងព័ត៌មានឯកជន។ សំឡេងនឹងផ្ទុកឡើងតែពេលចុច ផ្ញើ។ អត្ថបទសំឡេង និងចម្លើយ AI អាចខុស។',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('voice-send'),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: !busy && consent && available && retrySeconds == 0
                    ? send
                    : null,
                icon: const Icon(Icons.send_rounded),
                label: Text(text('Send recording', 'ផ្ញើការថត')),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              Notice(error!, error: true),
            ],
            if (retrySeconds > 0)
              Text(
                text(
                  'Retry in $retrySeconds seconds',
                  'សាកល្បងម្ដងទៀតក្នុង $retrySeconds វិនាទី',
                ),
              ),
            if (answer != null) ...[
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconFact(
                        Icons.hearing_rounded,
                        text('What I heard', 'អ្វីដែលខ្ញុំបានឮ'),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(string(answer!, 'transcript')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              CompanionAnswer(data: answer!),
              const SizedBox(height: 12),
              Notice(
                text(
                  'AI guidance · verify travel details before acting.',
                  'ការណែនាំ AI · សូមផ្ទៀងផ្ទាត់ព័ត៌មានធ្វើដំណើរមុនអនុវត្ត។',
                ),
                icon: Icons.verified_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
