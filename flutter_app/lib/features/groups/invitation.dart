import 'package:flutter/material.dart';
import '../../app/localization/strings.dart';
import '../../shared/components/components.dart';

Future<void> showInvite(BuildContext context) async {
  final form = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(c.t('invite')),
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(c.t('inviteBody')),
            const SizedBox(height: 16),
            TextFormField(
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: c.t('email')),
              validator: (v) =>
                  v != null && RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)
                  ? null
                  : c.t('required'),
            ),
            const SizedBox(height: 12),
            Text(c.t('member')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(c.t('cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(c);
              inform(context, context.t('demo'), context.t('inviteBody'));
            }
          },
          child: Text(c.t('confirm')),
        ),
      ],
    ),
  );
}
