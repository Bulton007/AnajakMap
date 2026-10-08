import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/localization/strings.dart';
import '../../app/theme/theme.dart';
import 'auth_copy.dart';
import 'auth_models.dart';

TextStyle authHeading(BuildContext context, double size) => TextStyle(
  fontFamily: context.isKhmer ? 'NotoSansKhmer' : 'CormorantGaramond',
  fontFamilyFallback: const ['NotoSansKhmer'],
  fontSize: context.isKhmer ? size * .77 : size,
  height: 1.16,
  fontWeight: FontWeight.w600,
);

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.onPreferences});
  final Widget child;
  final VoidCallback? onPreferences;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context);
    final scheme = base.colorScheme.copyWith(
      primary: dark ? const Color(0xFF92D4C2) : Tokens.authForest,
      onPrimary: dark ? Tokens.authForest : Colors.white,
      surface: dark ? const Color(0xFF162E2A) : Colors.white,
      onSurface: dark ? const Color(0xFFF0F4ED) : Tokens.authForest,
      onSurfaceVariant: dark ? const Color(0xFFB6CBC3) : Tokens.authMuted,
      outlineVariant: dark ? const Color(0xFF607A70) : Tokens.authBorder,
      secondaryContainer: dark ? const Color(0xFF23453D) : Tokens.authSoft,
      onSecondaryContainer: dark ? const Color(0xFFDFF1EA) : Tokens.authForest,
    );
    final ivory = dark ? const Color(0xFF10231F) : Tokens.authIvory;
    return Theme(
      data: base.copyWith(
        colorScheme: scheme,
        scaffoldBackgroundColor: ivory,
        textTheme: base.textTheme.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        ),
      ),
      child: Builder(
        builder: (context) => Scaffold(
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    children: [
                      AuthHero(onPreferences: onPreferences),
                      ColoredBox(
                        color: Tokens.authForest,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                          decoration: BoxDecoration(
                            color: ivory,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(32),
                            ),
                          ),
                          child: Material(
                            type: MaterialType.transparency,
                            child: child,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthHero extends StatelessWidget {
  const AuthHero({super.key, this.onPreferences});
  final VoidCallback? onPreferences;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      image: DecorationImage(
        image: AssetImage('assets/images/angkor.jpg'),
        fit: BoxFit.cover,
      ),
    ),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xAD0C2926), Color(0xE00C2926)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'anajak',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.6,
                    ),
                  ),
                ),
                if (onPreferences != null)
                  IconButton(
                    onPressed: onPreferences,
                    tooltip: context.t('language'),
                    icon: const Icon(Icons.language, color: Colors.white),
                    constraints: const BoxConstraints(
                      minHeight: 48,
                      minWidth: 48,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              context.a('authCompanion'),
              style: const TextStyle(
                color: Tokens.authGold,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Semantics(
              header: true,
              child: Text(
                context.a('authHero'),
                style: authHeading(context, 38).copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class AuthModeSelector extends StatelessWidget {
  const AuthModeSelector({
    super.key,
    required this.register,
    required this.onChanged,
    this.enabled = true,
  });
  final bool register, enabled;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final vertical =
          MediaQuery.textScalerOf(context).scale(14) > 23 ||
          constraints.maxWidth < 260;
      final buttons = [
        for (final mode in [false, true])
          Semantics(
            selected: register == mode,
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 52),
                backgroundColor: register == mode
                    ? Theme.of(context).colorScheme.surface
                    : Colors.transparent,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: register == mode
                        ? Theme.of(context).colorScheme.outlineVariant
                        : Colors.transparent,
                  ),
                ),
              ),
              onPressed: enabled ? () => onChanged(mode) : null,
              child: Text(context.a(mode ? 'authRegister' : 'authSignIn')),
            ),
          ),
      ];
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.secondaryContainer.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: vertical
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buttons,
              )
            : Row(
                children: [
                  for (final button in buttons) Expanded(child: button),
                ],
              ),
      );
    },
  );
}

class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.keyboardType,
    this.autofillHints,
    this.action = TextInputAction.next,
    this.onSubmitted,
    this.obscure = false,
    this.suffix,
    this.enabled = true,
    this.helper,
  });
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction action;
  final VoidCallback? onSubmitted;
  final bool obscure, enabled;
  final Widget? suffix;
  final String? helper;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: enabled,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: autofillHints,
          keyboardType: keyboardType,
          textInputAction: action,
          onFieldSubmitted: (_) => onSubmitted?.call(),
          validator: validator,
          decoration: InputDecoration(
            labelText: label,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            hintText: label,
            suffixIcon: suffix,
            helperText: helper,
            helperMaxLines: 8,
            errorMaxLines: 8,
            fillColor: Theme.of(context).colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.newPassword = false,
    this.guidance = false,
    this.enabled = true,
    this.action = TextInputAction.done,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final bool newPassword, guidance, enabled;
  final TextInputAction action;
  final VoidCallback? onSubmitted;
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool visible = false;
  @override
  Widget build(BuildContext context) => AuthTextField(
    controller: widget.controller,
    label: widget.label,
    validator: widget.validator,
    enabled: widget.enabled,
    obscure: !visible,
    keyboardType: TextInputType.visiblePassword,
    autofillHints: [
      widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
    ],
    action: widget.action,
    onSubmitted: widget.onSubmitted,
    helper: widget.guidance ? context.a('authPasswordRule') : null,
    suffix: IconButton(
      tooltip: context.a(visible ? 'authHidePassword' : 'authShowPassword'),
      onPressed: widget.enabled
          ? () => setState(() => visible = !visible)
          : null,
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    ),
  );
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size(48, 56)),
      child: loading
          ? Semantics(
              liveRegion: true,
              label: context.a('authWorking'),
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Text(label, textAlign: TextAlign.center),
    ),
  );
}

/// Supply a provider's official native/SDK button. No imitation logos or fake OAuth.
class SocialSignInButton extends StatelessWidget {
  const SocialSignInButton({
    super.key,
    required this.officialButton,
    required this.semanticLabel,
  });
  final Widget officialButton;
  final String semanticLabel;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      child: officialButton,
    ),
  );
}

class AuthInlineFeedback extends StatelessWidget {
  const AuthInlineFeedback(this.message, {super.key, this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: error
              ? Theme.of(context).colorScheme.onErrorContainer
              : Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    ),
  );
}

class AuthLegalConsent extends StatelessWidget {
  const AuthLegalConsent({
    super.key,
    required this.configuration,
    required this.value,
    required this.onChanged,
  });
  final AuthConfiguration configuration;
  final bool value;
  final ValueChanged<bool>? onChanged;
  Future<void> open(BuildContext context, Uri url) async {
    var success = false;
    try {
      success = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      /* Display a safe, localized error. */
    }
    if (!success && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.a('authLinkFailed'))));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: value,
        onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
        title: Text(context.a('authConsent')),
      ),
      Wrap(
        spacing: 12,
        children: [
          for (final item in [
            ('termsUrl', 'authTerms'),
            ('privacyUrl', 'authPrivacy'),
          ])
            TextButton(
              onPressed: configuration.legal(item.$1) == null
                  ? null
                  : () => open(context, configuration.legal(item.$1)!),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(context.a(item.$2)),
            ),
        ],
      ),
      if (!configuration.legalReady)
        AuthInlineFeedback(context.a('authLegalUnavailable')),
    ],
  );
}

class EmailVerificationPanel extends StatelessWidget {
  const EmailVerificationPanel({
    super.key,
    required this.email,
    required this.code,
    required this.onVerify,
    required this.onResend,
    this.retryAt,
    this.busy = false,
  });
  final String email;
  final TextEditingController code;
  final VoidCallback? onVerify, onResend;
  final DateTime? retryAt;
  final bool busy;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(email),
      const SizedBox(height: 12),
      Text(context.a('authVerifyInfo')),
      const SizedBox(height: 20),
      AuthTextField(
        controller: code,
        label: context.a('authCode'),
        enabled: !busy,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        action: TextInputAction.done,
        onSubmitted: onVerify,
        validator: (v) {
          final error = AuthValidation.code(v);
          return error == null ? null : context.a(error);
        },
      ),
      AuthPrimaryButton(
        label: context.a('authVerify'),
        onPressed: onVerify,
        loading: busy,
      ),
      AuthCooldownAction(
        retryAt: retryAt,
        onPressed: busy ? null : onResend,
        label: context.a('authResend'),
      ),
    ],
  );
}

class AuthCooldownAction extends StatefulWidget {
  const AuthCooldownAction({
    super.key,
    required this.retryAt,
    required this.onPressed,
    required this.label,
  });
  final DateTime? retryAt;
  final VoidCallback? onPressed;
  final String label;
  @override
  State<AuthCooldownAction> createState() => _AuthCooldownActionState();
}

class _AuthCooldownActionState extends State<AuthCooldownAction> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    schedule();
  }

  @override
  void didUpdateWidget(covariant AuthCooldownAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.retryAt != widget.retryAt) schedule();
  }

  void schedule() {
    timer?.cancel();
    final wait = widget.retryAt?.difference(DateTime.now());
    if (wait != null && !wait.isNegative) {
      timer = Timer(wait, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waiting = widget.retryAt?.isAfter(DateTime.now()) ?? false;
    return TextButton(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: waiting ? null : widget.onPressed,
      child: Text(
        waiting
            ? '${context.a('authRetryAt')} ${TimeOfDay.fromDateTime(widget.retryAt!).format(context)} (${widget.retryAt!.second.toString().padLeft(2, '0')}s)'
            : widget.label,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class GuestExploreAction extends StatelessWidget {
  const GuestExploreAction({super.key, required this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(minimumSize: const Size(48, 52)),
    child: Text(context.a('authGuest'), textAlign: TextAlign.center),
  );
}
