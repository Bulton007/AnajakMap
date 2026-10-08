import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage/app_state.dart';
import 'localization/strings.dart';
import 'router/router.dart';
import 'theme/theme.dart';

class AnajakApp extends ConsumerWidget {
  const AnajakApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    return MaterialApp.router(
      title: 'Anajak',
      debugShowCheckedModeBanner: false,
      theme: Tokens.theme(Brightness.light),
      darkTheme: Tokens.theme(Brightness.dark),
      themeMode: state.theme,
      locale: Locale(state.locale),
      supportedLocales: const [Locale('en'), Locale('km')],
      localizationsDelegates: const [
        Strings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }
}
