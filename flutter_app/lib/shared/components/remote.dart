import 'dart:convert';
import 'package:flutter/material.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../models/server_models.dart';
import 'components.dart';

class RemoteContent<T> extends StatefulWidget {
  const RemoteContent({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(T data, VoidCallback refresh) builder;
  @override
  State<RemoteContent<T>> createState() => _RemoteContentState<T>();
}

class _RemoteContentState<T> extends State<RemoteContent<T>> {
  late Future<T> future = widget.load();
  void refresh() => setState(() => future = widget.load());
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return Center(
          child: Semantics(
            label: context.t('loading'),
            child: const CircularProgressIndicator(),
          ),
        );
      }
      if (snapshot.hasError) {
        return PageBody(
          children: [
            Notice(
              '${context.t('requestFailed')}\n${snapshot.error}',
              error: true,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: refresh, child: Text(context.t('retry'))),
          ],
        );
      }
      return widget.builder(snapshot.data as T, refresh);
    },
  );
}

Future<T?> runRequest<T>(
  BuildContext context,
  Future<T> Function() task,
) async {
  try {
    return await task();
  } catch (e) {
    if (context.mounted) {
      await inform(context, context.t('requestFailed'), '$e');
    }
    return null;
  }
}

enum InputKind {
  text,
  email,
  password,
  amount,
  integer,
  number,
  date,
  instant,
  multiline,
}

class InputSpec {
  const InputSpec(
    this.key, {
    this.label,
    this.initial = '',
    this.kind = InputKind.text,
    this.choices,
    this.optional = false,
  });
  final String key, initial;
  final String? label;
  final InputKind kind;
  final List<String>? choices;
  final bool optional;
}

Future<Object?> remoteForm(
  BuildContext context,
  String title,
  List<InputSpec> fields, {
  String? notice,
  String submitLabel = 'save',
  Future<Object?> Function(Json, String)? submit,
}) => showModalBottomSheet<Object?>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _RemoteForm(
    title: title,
    fields: fields,
    notice: notice,
    submitLabel: submitLabel,
    submit: submit,
  ),
);

class _RemoteForm extends StatefulWidget {
  const _RemoteForm({
    required this.title,
    required this.fields,
    required this.submitLabel,
    this.notice,
    this.submit,
  });
  final String title, submitLabel;
  final String? notice;
  final List<InputSpec> fields;
  final Future<Object?> Function(Json, String)? submit;
  @override
  State<_RemoteForm> createState() => _RemoteFormState();
}

class _RemoteFormState extends State<_RemoteForm> {
  final form = GlobalKey<FormState>();
  late final controllers = {
    for (final f in widget.fields)
      f.key: TextEditingController(text: f.initial),
  };
  bool busy = false;
  Object? error;
  String operation = ApiClient.operationId(), lastPayload = '';
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Object? parse(InputSpec f, String v) {
    if (f.optional && v.isEmpty) {
      return null;
    }
    if (v.isEmpty) {
      throw FormatException(context.t('required'));
    }
    switch (f.kind) {
      case InputKind.amount:
        return decimalAmount(v);
      case InputKind.integer:
        return int.parse(v);
      case InputKind.number:
        final number = double.parse(v);
        if (!number.isFinite) {
          throw const FormatException();
        }
        return number;
      case InputKind.date:
        final date = DateTime.parse(v);
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ||
            date.toIso8601String().substring(0, 10) != v) {
          throw const FormatException();
        }
        return v;
      case InputKind.instant:
        if (!RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(v)) {
          throw FormatException(context.t('offsetHint'));
        }
        return DateTime.parse(v).toUtc().toIso8601String();
      case InputKind.email:
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
          throw const FormatException();
        }
        return v;
      case InputKind.password:
        if (v.length < 12 || utf8.encode(v).length > 72) {
          throw FormatException(context.t('password'));
        }
        return v;
      default:
        return v;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(widget.title),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (widget.notice != null) ...[
                const SizedBox(height: 16),
                Notice(widget.notice!),
              ],
              const SizedBox(height: 20),
              for (final f in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: f.choices != null
                      ? DropdownButtonFormField<String>(
                          initialValue: f.initial.isEmpty
                              ? f.choices!.first
                              : f.initial,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: context.t(f.label ?? f.key),
                          ),
                          items: f.choices!
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                          onChanged: busy
                              ? null
                              : (v) => controllers[f.key]!.text = v!,
                          validator: (_) {
                            if (controllers[f.key]!.text.isEmpty) {
                              controllers[f.key]!.text = f.choices!.first;
                            }
                            return null;
                          },
                        )
                      : TextFormField(
                          controller: controllers[f.key],
                          enabled: !busy,
                          obscureText: f.kind == InputKind.password,
                          maxLines: f.kind == InputKind.multiline ? 4 : 1,
                          keyboardType:
                              f.kind == InputKind.amount ||
                                  f.kind == InputKind.number
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                )
                              : f.kind == InputKind.email
                              ? TextInputType.emailAddress
                              : TextInputType.text,
                          decoration: InputDecoration(
                            labelText: context.t(f.label ?? f.key),
                            helperText: f.kind == InputKind.instant
                                ? context.t('offsetHint')
                                : f.kind == InputKind.date
                                ? 'YYYY-MM-DD'
                                : null,
                            suffixIcon: f.kind == InputKind.date
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.calendar_today_outlined,
                                    ),
                                    tooltip: context.t('dates'),
                                    onPressed: busy
                                        ? null
                                        : () async {
                                            final date = await showDatePicker(
                                              context: context,
                                              firstDate: DateTime(2000),
                                              lastDate: DateTime(2100),
                                              initialDate:
                                                  DateTime.tryParse(
                                                    controllers[f.key]!.text,
                                                  ) ??
                                                  DateTime.now(),
                                            );
                                            if (date != null) {
                                              controllers[f.key]!.text = date
                                                  .toIso8601String()
                                                  .substring(0, 10);
                                            }
                                          },
                                  )
                                : null,
                          ),
                          validator: (value) {
                            try {
                              parse(f, value?.trim() ?? '');
                              return null;
                            } catch (e) {
                              return e is FormatException &&
                                      e.message.isNotEmpty
                                  ? e.message
                                  : context.t('required');
                            }
                          },
                        ),
                ),
              if (error != null) ...[
                Notice('$error', error: true),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!form.currentState!.validate()) {
                            return;
                          }
                          final values = <String, dynamic>{
                            for (final f in widget.fields)
                              f.key: parse(f, controllers[f.key]!.text.trim()),
                          };
                          final payload = jsonEncode(values);
                          if (lastPayload.isNotEmpty &&
                              lastPayload != payload) {
                            operation = ApiClient.operationId();
                          }
                          lastPayload = payload;
                          setState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            final result = widget.submit == null
                                ? values
                                : await widget.submit!(values, operation);
                            if (context.mounted) {
                              Navigator.pop(context, result ?? true);
                            }
                          } catch (e) {
                            if (mounted) {
                              setState(() {
                                error = e;
                                busy = false;
                              });
                            }
                          }
                        },
                  child: Text(context.t(busy ? 'loading' : widget.submitLabel)),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: Text(context.t('cancel')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ServerResult extends StatelessWidget {
  const ServerResult(this.data, {super.key});
  final Object? data;
  String label(String key) {
    if (!key.contains('_')) {
      return key == key.toUpperCase() ? key.toLowerCase() : key;
    }
    final parts = key.toLowerCase().split('_');
    return parts.first +
        parts
            .skip(1)
            .map((v) => '${v[0].toUpperCase()}${v.substring(1)}')
            .join();
  }

  @override
  Widget build(BuildContext context) {
    if (data is List) {
      final list = data as List;
      return list.isEmpty
          ? Text(context.t('empty'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ServerResult(item),
                      ),
                    ),
                  ),
              ],
            );
    }
    if (data is Map) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in (data as Map).entries)
            if (e.value != null &&
                !['accessToken', 'refreshToken', 'objectKey'].contains(e.key))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: e.value is Map || e.value is List
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t(label(e.key.toString())),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          ServerResult(e.value),
                        ],
                      )
                    : SelectableText(
                        '${context.t(label(e.key.toString()))}: ${e.value}',
                      ),
              ),
        ],
      );
    }
    return SelectableText(data?.toString() ?? context.t('empty'));
  }
}

void openScreen(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
