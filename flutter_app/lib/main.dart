import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/app.dart';
import 'core/storage/app_state.dart';
import 'features/authentication/auth_links.dart';
import 'core/config/environment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Validate before creating repositories or restoring credentials.
  try {
    const environment = Environment();
    if (environment.release) environment.normalizedUrl;
  } on FormatException {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This build is not configured for service. Please contact Anajak support.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
      child: const AuthLinkListener(child: AnajakApp()),
    ),
  );
}
