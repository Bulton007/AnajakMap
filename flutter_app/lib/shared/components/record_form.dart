import 'package:flutter/material.dart';
import '../../app/localization/strings.dart';
import '../../shared/components/components.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/app_state.dart';
import '../../shared/models/travel.dart';

Future<void> showRecordForm(
  BuildContext context,
  WidgetRef ref,
  String tripId,
  String kind, {
  bool extraction = false,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) =>
        RecordForm(tripId: tripId, kind: kind, extraction: extraction),
  );
}

class RecordForm extends ConsumerStatefulWidget {
  const RecordForm({
    super.key,
    required this.tripId,
    required this.kind,
    required this.extraction,
  });
  final String tripId, kind;
  final bool extraction;
  @override
  ConsumerState<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends ConsumerState<RecordForm> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      amount = TextEditingController(),
      detail = TextEditingController();
  bool photo = false, reviewed = false, busy = false, initialized = false;
  String category = 'food';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized && widget.extraction) {
      title.text = context.t(
        widget.kind == 'expenses' ? 'sampleMeal' : 'sampleStay',
      );
      amount.text = '12.50';
      detail.text = widget.kind == 'reservations' ? 'DEMO-2048' : '';
    }
    initialized = true;
  }

  @override
  void dispose() {
    title.dispose();
    amount.dispose();
    detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expense = widget.kind == 'expenses';
    final reservation = widget.kind == 'reservations';
    final journal = widget.kind == 'journal';
    return PopScope(
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
                  context.t(
                    widget.extraction
                        ? 'extraction'
                        : expense
                        ? 'addExpense'
                        : reservation
                        ? 'addReservation'
                        : journal
                        ? 'newEntry'
                        : 'createGroup',
                  ),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),
                if (widget.extraction) ...[
                  Notice(
                    context.t('extractionBody'),
                    icon: Icons.document_scanner_outlined,
                  ),
                  const SizedBox(height: 14),
                  Pill(context.t('uncertain'), icon: Icons.rule),
                  const SizedBox(height: 18),
                ],
                TextFormField(
                  controller: title,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: context.t(
                      widget.kind == 'group' ? 'groupName' : 'title',
                    ),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? context.t('required')
                      : null,
                ),
                const SizedBox(height: 12),
                if (expense) ...[
                  TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(labelText: context.t('amount')),
                    validator: (v) => parseMoney(v ?? '') == null
                        ? context.t('invalidAmount')
                        : null,
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: InputDecoration(
                      labelText: context.t('category'),
                    ),
                    items: ['food', 'culture', 'nature']
                        .map(
                          (k) => DropdownMenuItem(
                            value: k,
                            child: Text(context.t(k)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => category = v!,
                  ),
                  const SizedBox(height: 18),
                ],
                if (reservation || journal) ...[
                  TextFormField(
                    controller: detail,
                    maxLines: journal ? 4 : 1,
                    maxLength: journal ? 3000 : 100,
                    decoration: InputDecoration(
                      labelText: context.t(journal ? 'note' : 'reference'),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? context.t('required')
                        : null,
                  ),
                  const SizedBox(height: 14),
                ],
                if (reservation) ...[
                  Notice(context.t('noReservationsBody')),
                  const SizedBox(height: 14),
                ],
                if (journal) ...[
                  OutlinedButton.icon(
                    onPressed: () => setState(() => photo = !photo),
                    icon: Icon(
                      photo
                          ? Icons.check_circle_outline
                          : Icons.add_photo_alternate_outlined,
                    ),
                    label: Text(context.t(photo ? 'photoAttached' : 'attach')),
                  ),
                  const SizedBox(height: 18),
                ],
                if (widget.extraction)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: reviewed,
                    onChanged: (v) => setState(() => reviewed = v!),
                    title: Text(context.t('confirm')),
                    subtitle: Text(context.t('uncertain')),
                  ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy || widget.extraction && !reviewed
                        ? null
                        : () async {
                            if (!form.currentState!.validate()) {
                              return;
                            }
                            setState(() => busy = true);
                            final record = TravelRecord(
                              id: DateTime.now().microsecondsSinceEpoch
                                  .toString(),
                              tripId: widget.tripId,
                              kind: widget.kind,
                              title: title.text.trim(),
                              detail: expense
                                  ? context.t(category)
                                  : detail.text.trim(),
                              cents: expense ? parseMoney(amount.text)! : 0,
                              photo: photo,
                            );
                            final ok = await persist(
                              context,
                              () => ref
                                  .read(appStateProvider.notifier)
                                  .addRecord(record),
                            );
                            if (context.mounted) {
                              if (ok) {
                                Navigator.pop(context);
                              } else {
                                setState(() => busy = false);
                              }
                            }
                          },
                    child: Text(context.t(busy ? 'loading' : 'save')),
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
}
