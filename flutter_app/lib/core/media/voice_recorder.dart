import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

const voiceMaxDuration = Duration(seconds: 60);
const voiceMaxBytes = 4 * 1024 * 1024;

class VoiceRecording {
  const VoiceRecording({required this.bytes, required this.duration});
  final Uint8List bytes;
  final Duration duration;
}

class VoiceRecorderFailure implements Exception {
  const VoiceRecorderFailure(this.code);
  final String code;
}

/// Validates the native format and bounds the actual PCM samples, even if a
/// platform stop callback arrives after the 60-second timer.
VoiceRecording boundedVoiceWav(Uint8List bytes) {
  if (bytes.length <= 44 ||
      bytes.length > voiceMaxBytes ||
      String.fromCharCodes(bytes.take(4)) != 'RIFF' ||
      String.fromCharCodes(bytes.skip(8).take(4)) != 'WAVE') {
    throw const VoiceRecorderFailure('UNSUPPORTED');
  }
  final header = ByteData.sublistView(bytes);
  bool pcm = false;
  for (var offset = 12; offset + 8 <= bytes.length;) {
    final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final length = header.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (start + length > bytes.length) break;
    if (type == 'fmt ' && length >= 16) {
      pcm =
          header.getUint16(start, Endian.little) == 1 &&
          header.getUint16(start + 2, Endian.little) == 1 &&
          header.getUint32(start + 4, Endian.little) == 16000 &&
          header.getUint16(start + 12, Endian.little) == 2 &&
          header.getUint16(start + 14, Endian.little) == 16;
    }
    if (type == 'data' && pcm && length > 0 && length.isEven) {
      final kept = length.clamp(0, 16000 * 2 * voiceMaxDuration.inSeconds);
      final bounded = Uint8List.fromList(bytes.sublist(0, start + kept));
      final boundedHeader = ByteData.sublistView(bounded);
      boundedHeader.setUint32(4, bounded.length - 8, Endian.little);
      boundedHeader.setUint32(offset + 4, kept, Endian.little);
      return VoiceRecording(
        bytes: bounded,
        duration: Duration(microseconds: kept * 1000000 ~/ 32000),
      );
    }
    offset = start + length + (length.isOdd ? 1 : 0);
  }
  throw const VoiceRecorderFailure('UNSUPPORTED');
}

abstract interface class VoiceRecorder {
  Future<void> start();
  Future<VoiceRecording> stop();
  Future<void> cancel();
  Future<void> dispose();
}

final voiceRecorderProvider = Provider.autoDispose<VoiceRecorder>((ref) {
  final recorder = NativeVoiceRecorder();
  ref.onDispose(() => unawaited(recorder.dispose()));
  return recorder;
});

/// WAV recordings are private temporary files, never gallery or shared files.
/// After stop the file is deleted; only a bounded in-memory copy remains.
class NativeVoiceRecorder implements VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  File? _file;
  Timer? _deadline;
  Future<VoiceRecording>? _stopping;
  Future<void>? _disposing;
  Future<void> _work = Future<void>.value();
  bool _disposed = false;
  bool _active = false;
  int _generation = 0;

  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _work.then((_) => action());
    _work = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw const VoiceRecorderFailure('CANCELLED');
    }
  }

  @override
  Future<void> start() {
    final generation = ++_generation;
    return _serialize(() => _start(generation));
  }

  Future<void> _start(int generation) async {
    _check(generation);
    if (_disposed || _active) {
      throw const VoiceRecorderFailure('UNAVAILABLE');
    }
    _stopping = null;
    try {
      final allowed = await _recorder.hasPermission();
      _check(generation);
      if (!allowed) throw const VoiceRecorderFailure('PERMISSION');
      if (!await _recorder.isEncoderSupported(AudioEncoder.wav)) {
        throw const VoiceRecorderFailure('UNSUPPORTED');
      }
      _check(generation);
      final directory = await getTemporaryDirectory();
      _check(generation);
      _file = File(
        '${directory.path}${Platform.pathSeparator}anajak-voice-${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          audioInterruption: AudioInterruptionMode.pause,
        ),
        path: _file!.path,
      );
      _check(generation);
      _active = true;
      _deadline = Timer(voiceMaxDuration, () {
        // UI also stops at the limit. This native guard still applies if the
        // screen's elapsed-time callback is delayed.
        unawaited(stop().then<void>((_) {}, onError: (Object _) {}));
      });
    } catch (_) {
      await _cancelNative();
      rethrow;
    }
  }

  @override
  Future<VoiceRecording> stop() => _stopping ??= _serialize(_finish);

  Future<VoiceRecording> _finish() async {
    if (!_active || _disposed) {
      throw const VoiceRecorderFailure('EMPTY');
    }
    final generation = _generation;
    _deadline?.cancel();
    _active = false;
    try {
      // Trust only the private path created above, not a platform-returned path.
      await _recorder.stop();
      _check(generation);
      final file = _file;
      if (file == null) throw const VoiceRecorderFailure('EMPTY');
      final length = await file.length();
      if (length <= 44 || length > voiceMaxBytes) {
        throw const VoiceRecorderFailure('SIZE');
      }
      final bytes = await file.readAsBytes();
      _check(generation);
      return boundedVoiceWav(bytes);
    } finally {
      await _deletePrivateFile();
    }
  }

  Future<void> _deletePrivateFile() async {
    final file = _file;
    _file = null;
    if (file != null && await file.exists()) await file.delete();
  }

  @override
  Future<void> cancel() {
    ++_generation;
    _deadline?.cancel();
    _active = false;
    _stopping = null;
    return _serialize(_cancelNative);
  }

  Future<void> _cancelNative() async {
    try {
      if (!_disposed) await _recorder.cancel();
    } catch (_) {
      // Cleanup must also run after an interruption or native recorder failure.
    } finally {
      await _deletePrivateFile();
    }
  }

  @override
  Future<void> dispose() {
    if (_disposing != null) return _disposing!;
    ++_generation;
    _deadline?.cancel();
    return _disposing = _serialize(_dispose);
  }

  Future<void> _dispose() async {
    if (_disposed) return;
    await _cancelNative();
    _disposed = true;
    await _recorder.dispose();
  }
}
