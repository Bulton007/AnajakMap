import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/components/components.dart';

Future<Json?> uploadMedia(
  BuildContext context,
  String path, {
  String? tripId,
  bool audio = false,
  bool imagesOnly = false,
}) => showModalBottomSheet<Json>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) =>
      _Upload(path: path, tripId: tripId, audio: audio, imagesOnly: imagesOnly),
);

class _Upload extends ConsumerStatefulWidget {
  const _Upload({
    required this.path,
    this.tripId,
    this.audio = false,
    this.imagesOnly = false,
  });
  final String path;
  final String? tripId;
  final bool audio;
  final bool imagesOnly;
  @override
  ConsumerState<_Upload> createState() => _UploadState();
}

class _UploadState extends ConsumerState<_Upload> {
  CancelToken? cancel;
  double progress = 0;
  bool busy = false;
  Object? error;
  @override
  void dispose() {
    cancel?.cancel();
    super.dispose();
  }

  Future<void> pick(bool camera) async {
    try {
      XFile? file;
      if (camera) {
        file = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 2000,
          imageQuality: 85,
        );
      } else {
        final result = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: widget.audio
              ? ['mp3', 'wav']
              : widget.imagesOnly
              ? ['png', 'jpg', 'jpeg']
              : ['png', 'jpg', 'jpeg', 'pdf'],
        );
        file = result?.xFile;
      }
      if (file == null || !mounted) {
        return;
      }
      final bytes = await file.readAsBytes();
      final max = widget.imagesOnly
          ? 4
          : widget.path.startsWith('guide') ||
                widget.path.startsWith('expenses')
          ? 5
          : 10;
      if (bytes.isEmpty || bytes.length > max * 1024 * 1024) {
        throw FormatException('Maximum $max MB');
      }
      final ext = file.name.split('.').last.toLowerCase();
      final mime = {
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'pdf': 'application/pdf',
        'mp3': 'audio/mpeg',
        'wav': 'audio/wav',
      }[ext];
      if (mime == null ||
          (widget.imagesOnly && !['image/png', 'image/jpeg'].contains(mime))) {
        throw const FormatException('Unsupported file');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        busy = true;
        error = null;
        progress = 0;
        cancel = CancelToken();
      });
      final result = await ref
          .read(repositoryProvider)
          .upload(
            widget.path,
            bytes,
            file.name,
            mime,
            tripId: widget.tripId,
            cancel: cancel,
            progress: (sent, total) {
              if (mounted && total > 0) {
                setState(() => progress = sent / total);
              }
            },
          );
      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('chooseFile'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        Notice(context.t('uploadNotice')),
        const SizedBox(height: 16),
        if (busy) ...[
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 12),
          Text('${context.t('uploading')} ${(progress * 100).round()}%'),
          TextButton(
            onPressed: () => cancel?.cancel(),
            child: Text(context.t('cancel')),
          ),
        ] else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => pick(false),
                icon: const Icon(Icons.upload_file),
                label: Text(context.t('chooseFile')),
              ),
              if (!widget.audio)
                OutlinedButton.icon(
                  onPressed: () => pick(true),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(context.t('takePhoto')),
                ),
            ],
          ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Notice('$error', error: true),
        ],
      ],
    ),
  );
}
