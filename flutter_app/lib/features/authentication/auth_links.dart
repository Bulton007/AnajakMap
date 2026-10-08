import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/router/router.dart';
import 'auth_controller.dart';
import 'auth_models.dart';

final pendingAuthLinkProvider = NotifierProvider<PendingAuthLink, AuthLink?>(
  PendingAuthLink.new,
);

class PendingAuthLink extends Notifier<AuthLink?> {
  @override
  AuthLink? build() => null;
  void set(AuthLink link) => state = link;
  void clear() => state = null;
}

class AuthLinkListener extends ConsumerStatefulWidget {
  const AuthLinkListener({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<AuthLinkListener> createState() => _AuthLinkListenerState();
}

class _AuthLinkListenerState extends ConsumerState<AuthLinkListener> {
  StreamSubscription<Uri>? subscription;
  @override
  void initState() {
    super.initState();
    if (const String.fromEnvironment('AUTH_LINK_BASE').isNotEmpty) {
      final links = AppLinks();
      subscription = links.uriLinkStream.listen(receive, onError: (_) {});
      links
          .getInitialLink()
          .then((uri) {
            if (uri != null) receive(uri);
          })
          .catchError((Object _) {});
    }
  }

  void receive(Uri uri) {
    if (!mounted || ref.read(authControllerProvider).authenticated) return;
    final link = AuthLink.parse(
      uri,
      const String.fromEnvironment('AUTH_LINK_BASE'),
    );
    if (link == null) {
      final base = Uri.tryParse(const String.fromEnvironment('AUTH_LINK_BASE'));
      if (base == null ||
          uri.scheme != 'https' ||
          !uri.hasAuthority ||
          uri.origin != base.origin ||
          uri.path != base.path) {
        return;
      }
      ref
          .read(pendingAuthLinkProvider.notifier)
          .set(const AuthLink(AuthFlow.reset, '', ''));
    } else {
      ref.read(pendingAuthLinkProvider.notifier).set(link);
    }
    ref.read(routerProvider).go('/auth');
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
