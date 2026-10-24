import 'package:flutter/material.dart';
import '../rpg/rpg_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/profile/profile.dart';
import 'auth_components.dart';
import 'auth_controller.dart';
import 'auth_copy.dart';
import 'auth_models.dart';
import 'auth_links.dart';

class AuthenticationScreen extends ConsumerStatefulWidget {
  const AuthenticationScreen({super.key});
  @override
  ConsumerState<AuthenticationScreen> createState() => _AuthenticationState();
}

class _AuthenticationState extends ConsumerState<AuthenticationScreen>
    with WidgetsBindingObserver {
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController(),
      code = TextEditingController(),
      confirmation = TextEditingController();
  final form = GlobalKey<FormState>();
  bool consent = false;
  AuthLink? usedLink;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(authConfigurationProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final field in [email, password, name, code, confirmation]) {
      field.dispose();
    }
    super.dispose();
  }

  void change(AuthFlow flow) {
    FocusScope.of(context).unfocus();
    form.currentState?.reset();
    password.clear();
    confirmation.clear();
    code.clear();
    setState(() => consent = false);
    ref.read(authControllerProvider.notifier).flow(flow, email: email.text);
  }

  String? validate(String? Function(String?) validator, String? value) {
    final key = validator(value);
    return key == null ? null : context.a(key);
  }

  Future<void> submit(AuthFlow flow, AuthConfiguration config) async {
    if (!(form.currentState?.validate() ?? false)) return;
    final auth = ref.read(authControllerProvider.notifier);
    FocusScope.of(context).unfocus();
    switch (flow) {
      case AuthFlow.signIn:
        await auth.login(email.text, password.text);
      case AuthFlow.register:
        await auth.register(
          name.text,
          email.text,
          password.text,
          consent,
          config.policyVersion,
        );
      case AuthFlow.forgot:
        await auth.recover(email.text);
      case AuthFlow.verify:
        await auth.verify(email.text, code.text);
      case AuthFlow.reset:
        await auth.reset(email.text, code.text, password.text);
    }
    if (!mounted) return;
    final result = ref.read(authControllerProvider);
    if (result.authenticated) TextInput.finishAutofillContext(shouldSave: true);
    if (result.phase != AuthPhase.error) {
      password.clear();
      confirmation.clear();
    }
    if (result.phase == AuthPhase.verified ||
        result.phase == AuthPhase.resetComplete) {
      code.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final configuration = ref.watch(authConfigurationProvider);
    final config = configuration.asData?.value ?? const AuthConfiguration({});
    final link = ref.watch(pendingAuthLinkProvider);
    if (link != null && link != usedLink && !state.busy) {
      usedLink = link;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        email.text = link.email;
        code.text = link.code;
        ref.read(authControllerProvider.notifier).acceptLink(link);
        ref.read(pendingAuthLinkProvider.notifier).clear();
      });
    }
    if (email.text.isEmpty && state.email.isNotEmpty) email.text = state.email;
    final flow = state.flow;
    final registering = flow == AuthFlow.register;
    final verifying = flow == AuthFlow.verify;
    final resetting = flow == AuthFlow.reset;
    final success =
        state.phase == AuthPhase.verified ||
        state.phase == AuthPhase.resetComplete;
    final title = verifying
        ? 'authVerifyHeading'
        : resetting || flow == AuthFlow.forgot
        ? 'authRecover'
        : 'authHeading';
    final limited = state.failure?.retryAt?.isAfter(DateTime.now()) ?? false;
    final enabled =
        !state.busy &&
        !limited &&
        (flow != AuthFlow.register || (config.registration && consent)) &&
        (flow != AuthFlow.forgot || config.emailDelivery);
    void send() {
      if (enabled) submit(flow, config);
    }

    return AuthScaffold(
      onPreferences: () => showPreferences(context),
      child: AutofillGroup(
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(context.a(title), style: authHeading(context, 42)),
              ),
              const SizedBox(height: 8),
              Text(context.a('authIntro')),
              const SizedBox(height: 24),
              if (state.phase == AuthPhase.restoring) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 18),
                Text(context.a('authRestoring'), textAlign: TextAlign.center),
              ] else ...[
                if (flow == AuthFlow.signIn || registering) ...[
                  AuthModeSelector(
                    register: registering,
                    enabled: !state.busy,
                    onChanged: (register) =>
                        change(register ? AuthFlow.register : AuthFlow.signIn),
                  ),
                  const SizedBox(height: 24),
                ],
                if (state.failure != null)
                  AuthInlineFeedback(
                    context.a(state.failure!.key),
                    error: true,
                  ),
                if (state.failure?.retryAt != null)
                  AuthCooldownAction(
                    retryAt: state.failure!.retryAt,
                    onPressed: state.busy ? null : () => setState(() {}),
                    label: context.a('authRetry'),
                  ),
                if (configuration.hasError) ...[
                  AuthInlineFeedback(context.a('authNetwork'), error: true),
                  TextButton(
                    onPressed: () => ref.invalidate(authConfigurationProvider),
                    child: Text(context.a('authRetry')),
                  ),
                ],
                if (configuration.hasValue &&
                    !config.emailDelivery &&
                    !success) ...[
                  AuthInlineFeedback(context.a('authUnavailable')),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: state.busy || configuration.isLoading
                          ? null
                          : () => ref.invalidate(authConfigurationProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(context.a('authCheckAgain')),
                    ),
                  ),
                ],
                if (registering &&
                    config.policyVersion.startsWith('local-test-'))
                  AuthInlineFeedback(context.a('authLocalTest')),
                if (success) ...[
                  AuthInlineFeedback(
                    context.a(
                      state.phase == AuthPhase.verified
                          ? 'authVerified'
                          : 'authResetComplete',
                    ),
                  ),
                  AuthPrimaryButton(
                    label: context.a('authBack'),
                    onPressed: () => change(AuthFlow.signIn),
                  ),
                ] else if (verifying) ...[
                  AuthTextField(
                    controller: email,
                    label: context.a('authEmail'),
                    enabled: !state.busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) => validate(AuthValidation.email, v),
                  ),
                  EmailVerificationPanel(
                    email: email.text,
                    code: code,
                    busy: state.busy,
                    retryAt: state.retryAt,
                    onVerify: enabled ? send : null,
                    onResend: config.emailDelivery
                        ? () {
                            if (AuthValidation.email(email.text) == null) {
                              ref
                                  .read(authControllerProvider.notifier)
                                  .resend(email.text);
                            } else {
                              form.currentState?.validate();
                            }
                          }
                        : null,
                  ),
                ] else ...[
                  if (state.phase == AuthPhase.recoverySent)
                    AuthInlineFeedback(context.a('authRecoverySent')),
                  if (registering)
                    AuthTextField(
                      controller: name,
                      label: context.a('authName'),
                      enabled: !state.busy,
                      autofillHints: const [AutofillHints.name],
                      keyboardType: TextInputType.name,
                      validator: (v) => validate(AuthValidation.name, v),
                    ),
                  AuthTextField(
                    controller: email,
                    label: context.a('authEmail'),
                    enabled: !state.busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: [
                      registering
                          ? AutofillHints.newUsername
                          : AutofillHints.username,
                    ],
                    action: flow == AuthFlow.forgot
                        ? TextInputAction.done
                        : TextInputAction.next,
                    onSubmitted: flow == AuthFlow.forgot ? send : null,
                    validator: (v) => validate(AuthValidation.email, v),
                  ),
                  if (resetting)
                    AuthTextField(
                      controller: code,
                      label: context.a('authCode'),
                      enabled: !state.busy,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      validator: (v) => validate(AuthValidation.code, v),
                    ),
                  if (flow != AuthFlow.forgot)
                    PasswordField(
                      controller: password,
                      label: context.a(
                        resetting ? 'authNewPassword' : 'authPassword',
                      ),
                      enabled: !state.busy,
                      newPassword: registering || resetting,
                      guidance: registering || resetting,
                      action: resetting
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onSubmitted: resetting ? null : send,
                      validator: (v) => validate(AuthValidation.password, v),
                    ),
                  if (resetting)
                    PasswordField(
                      controller: confirmation,
                      label: context.a('authConfirmPassword'),
                      enabled: !state.busy,
                      newPassword: true,
                      validator: (v) =>
                          v == password.text ? null : context.a('authMismatch'),
                      onSubmitted: send,
                    ),
                  if (flow == AuthFlow.signIn)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: state.busy
                            ? null
                            : () => change(AuthFlow.forgot),
                        child: Text(context.a('authForgot')),
                      ),
                    ),
                  if (registering) ...[
                    AuthLegalConsent(
                      configuration: config,
                      value: consent,
                      onChanged: state.busy || !config.legalReady
                          ? null
                          : (value) => setState(() => consent = value),
                    ),
                    const SizedBox(height: 16),
                  ],
                  AuthPrimaryButton(
                    label: context.a(
                      registering
                          ? 'authRegister'
                          : resetting
                          ? 'authReset'
                          : flow == AuthFlow.forgot
                          ? 'authSendReset'
                          : 'authSignIn',
                    ),
                    loading: state.busy,
                    onPressed: enabled ? send : null,
                  ),
                  if (flow == AuthFlow.forgot)
                    TextButton(
                      onPressed: state.busy
                          ? null
                          : () => change(AuthFlow.reset),
                      child: Text(context.a('authHaveCode')),
                    ),
                  if (resetting)
                    AuthCooldownAction(
                      retryAt: state.retryAt,
                      onPressed: state.busy || !config.emailDelivery
                          ? null
                          : () => ref
                                .read(authControllerProvider.notifier)
                                .recover(email.text),
                      label: context.a('authSendReset'),
                    ),
                ],
                if (flow != AuthFlow.signIn && !success)
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: state.busy
                        ? null
                        : () => change(AuthFlow.signIn),
                    child: Text(context.a('authBack')),
                  ),
                if (flow == AuthFlow.signIn && !success) ...[
                  TextButton(
                    onPressed: state.busy
                        ? null
                        : () => change(AuthFlow.verify),
                    child: Text(context.a('authVerify')),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    context.a('authProviderUnavailable'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                GuestExploreAction(
                  onPressed: state.busy
                      ? null
                      : () {
                          password.clear();
                          confirmation.clear();
                          code.clear();
                          TextInput.finishAutofillContext(shouldSave: false);
                          ref.read(authControllerProvider.notifier).guest();
                          context.go('/guest');
                        },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AuthGuestScreen extends StatelessWidget {
  const AuthGuestScreen({super.key});
  @override
  Widget build(BuildContext context) => AuthScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.a('authGuestPlace'), style: authHeading(context, 40)),
        const SizedBox(height: 16),
        AuthInlineFeedback(context.a('authGuestInfo')),
        Text(context.a('authGuestDescription')),
        const RpgEntry(),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: context.a('authSignIn'),
          onPressed: () => context.go('/auth?from=%2Fconnected'),
        ),
      ],
    ),
  );
}
