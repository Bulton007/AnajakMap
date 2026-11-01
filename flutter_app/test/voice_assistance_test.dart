import 'dart:async';
import 'dart:typed_data';
import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/core/media/voice_recorder.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/features/connected/voice_assistance.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'connected_contract_test.dart'
    show MemoryCredentials, Transport, response;

Uint8List wav({int seconds = 2, int sampleRate = 16000}) {
  final bytes = Uint8List(44 + seconds * sampleRate * 2);
  final header = ByteData.sublistView(bytes);
  void tag(int offset, String value) =>
      bytes.setRange(offset, offset + 4, value.codeUnits);
  tag(0, 'RIFF');
  header.setUint32(4, bytes.length - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  header.setUint32(40, bytes.length - 44, Endian.little);
  return bytes;
}

class FakeRecorder implements VoiceRecorder {
  int started = 0, stopped = 0, cancelled = 0, disposed = 0;
  Object? startFailure;
  Completer<void>? pendingStart;
  @override
  Future<void> start() async {
    started++;
    if (pendingStart != null) await pendingStart!.future;
    if (startFailure != null) throw startFailure!;
  }

  @override
  Future<VoiceRecording> stop() async {
    stopped++;
    return VoiceRecording(bytes: wav(), duration: const Duration(seconds: 2));
  }

  @override
  Future<void> cancel() async {
    cancelled++;
  }

  @override
  Future<void> dispose() async {
    disposed++;
  }
}

class VoiceHarness {
  final recorder = FakeRecorder();
  final requests = <RequestOptions>[];
  Completer<ResponseBody>? pending;
  bool offline = false;
  Json answer = {
    'transcript': 'What can I visit in Kampot?',
    'text': 'Consider a riverside walk during daylight.',
    'source': 'Google Gemini',
    'mock': false,
    'requiresVerification': true,
  };
  late final api = ApiClient(
    'https://example.test/api/v1/',
    MemoryCredentials(),
    transport: Dio()
      ..httpClientAdapter = Transport((request) async {
        requests.add(request);
        if (offline) {
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
          );
        }
        if (request.path == 'guide/media') {
          return response({'mediaId': 'owned-audio'});
        }
        return pending == null ? response(answer) : pending!.future;
      }),
  );

  Future<void> show(
    WidgetTester tester, {
    bool available = true,
    String locale = 'en',
    double scale = 1,
  }) async {
    await tester.runAsync(() => Strings.delegate.load(Locale(locale)));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          voiceRecorderProvider.overrideWithValue(recorder),
          apiProvider.overrideWithValue(api),
          guideCapabilitiesProvider.overrideWith(
            (ref) async => {'voice': available},
          ),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('en'), Locale('km')],
          theme: Tokens.theme(Brightness.dark),
          localizationsDelegates: const [
            Strings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const VoiceAssistanceScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
  }

  Future<void> record(WidgetTester tester) async {
    await press(tester, 'voice-record');
    await tester.pump();
    await press(tester, 'voice-record');
    await tester.pumpAndSettle();
  }

  Future<void> consent(WidgetTester tester) => press(tester, 'voice-consent');
}

void main() {
  test(
    'native WAV decoder preserves valid PCM and bounds actual samples to 60 seconds',
    () {
      final short = boundedVoiceWav(wav(seconds: 2));
      expect(short.duration, const Duration(seconds: 2));
      final bounded = boundedVoiceWav(wav(seconds: 61));
      expect(bounded.duration, voiceMaxDuration);
      expect(bounded.bytes.length, 44 + 60 * 32000);
      expect(
        ByteData.sublistView(bounded.bytes).getUint32(40, Endian.little),
        60 * 32000,
      );
      expect(
        () => boundedVoiceWav(wav(sampleRate: 44100)),
        throwsA(isA<VoiceRecorderFailure>()),
      );
      expect(
        () => boundedVoiceWav(Uint8List(voiceMaxBytes + 1)),
        throwsA(isA<VoiceRecorderFailure>()),
      );
    },
  );
  testWidgets('permission denial never records or uploads', (tester) async {
    final harness = VoiceHarness()
      ..recorder.startFailure = const VoiceRecorderFailure('PERMISSION');
    await harness.show(tester);
    await harness.press(tester, 'voice-record');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Microphone permission was denied'),
      findsOneWidget,
    );
    expect(harness.recorder.stopped, 0);
    expect(harness.requests, isEmpty);
  });
  testWidgets(
    'first permission dialog may be inactive without cancelling start',
    (tester) async {
      final harness = VoiceHarness()..recorder.pendingStart = Completer<void>();
      await harness.show(tester);
      try {
        await harness.press(tester, 'voice-record');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(harness.recorder.cancelled, 0);
        expect(harness.requests, isEmpty);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        harness.recorder.pendingStart!.complete();
        await tester.pump();
        expect(find.text('Stop recording'), findsOneWidget);
        expect(harness.recorder.started, 1);
        expect(harness.recorder.cancelled, 0);
        expect(harness.requests, isEmpty);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets('backgrounding during permission wait prevents a delayed start', (
    tester,
  ) async {
    final harness = VoiceHarness()..recorder.pendingStart = Completer<void>();
    await harness.show(tester);
    try {
      await harness.press(tester, 'voice-record');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(harness.recorder.cancelled, greaterThan(0));
      harness.recorder.pendingStart!.complete();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Stop recording'), findsNothing);
      expect(find.text('Record question'), findsOneWidget);
      expect(harness.recorder.started, 1);
      expect(harness.requests, isEmpty);
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets(
    'record and stop stay local and unchecked consent blocks sending',
    (tester) async {
      final harness = VoiceHarness();
      await harness.show(tester);
      await harness.record(tester);
      expect(harness.recorder.started, 1);
      expect(harness.recorder.stopped, 1);
      expect(harness.requests, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('voice-send')))
            .onPressed,
        isNull,
      );
      await harness.press(tester, 'voice-send');
      expect(harness.requests, isEmpty);
    },
  );
  testWidgets(
    'explicit Send uploads WAV once and renders confirmed transcript and answer',
    (tester) async {
      final harness = VoiceHarness();
      await harness.show(tester);
      await harness.record(tester);
      await harness.consent(tester);
      expect(harness.requests, isEmpty);
      await harness.press(tester, 'voice-send');
      await tester.pumpAndSettle();
      expect(harness.requests.map((r) => r.path), [
        'guide/media',
        'guide/voice',
      ]);
      final upload = harness.requests.first.data as FormData;
      expect(upload.files.single.value.contentType.toString(), 'audio/wav');
      expect(harness.requests.last.data, {
        // Spring GuideApi.Input requires this envelope, shared with vision.
        'input': {
          'mediaId': 'owned-audio',
          'shareWithProvider': true,
          'language': 'en',
        },
      });
      expect(find.text('What can I visit in Kampot?'), findsOneWidget);
      expect(
        find.text('Consider a riverside walk during daylight.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('duplicate Send is blocked while a voice answer is pending', (
    tester,
  ) async {
    final harness = VoiceHarness()..pending = Completer<ResponseBody>();
    await harness.show(tester);
    await harness.record(tester);
    await harness.consent(tester);
    await harness.press(tester, 'voice-send');
    for (var frame = 0; frame < 20 && harness.requests.isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await harness.press(tester, 'voice-send');
    expect(harness.requests.where((r) => r.path == 'guide/media').length, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('voice-send')))
          .onPressed,
      isNull,
    );
    harness.pending!.complete(response(harness.answer));
    await tester.pumpAndSettle();
    expect(harness.requests.where((r) => r.path == 'guide/voice').length, 1);
    expect(find.text('What can I visit in Kampot?'), findsOneWidget);
  });
  testWidgets('leaving the app or disposing cancels recording without upload', (
    tester,
  ) async {
    final harness = VoiceHarness();
    await harness.show(tester);
    await harness.press(tester, 'voice-record');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(harness.recorder.cancelled, greaterThan(0));
    expect(harness.requests, isEmpty);
    expect(
      find.textContaining('Recording stopped when the app left'),
      findsOneWidget,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    expect(harness.recorder.cancelled, greaterThan(1));
  });
  testWidgets('unavailable server disables recording honestly', (tester) async {
    final harness = VoiceHarness();
    await harness.show(tester, available: false);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('voice-record')))
          .onPressed,
      isNull,
    );
    expect(
      find.textContaining('Voice assistance is unavailable'),
      findsOneWidget,
    );
    expect(harness.requests, isEmpty);
  });
  testWidgets(
    'network failure preserves the local recording and consent for explicit retry',
    (tester) async {
      final harness = VoiceHarness()..offline = true;
      await harness.show(tester);
      await harness.record(tester);
      await harness.consent(tester);
      await harness.press(tester, 'voice-send');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No connection. Your recording is kept'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('voice-consent')))
            .value,
        true,
      );
      expect(find.byKey(const Key('voice-send')), findsOneWidget);
    },
  );
  testWidgets(
    'Khmer large-text screen remains scrollable with reachable controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = VoiceHarness();
      await harness.show(tester, locale: 'km', scale: 2);
      await harness.record(tester);
      await tester.ensureVisible(find.byKey(const Key('voice-send')));
      expect(tester.takeException(), isNull);
    },
  );
}
