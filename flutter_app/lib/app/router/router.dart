import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/storage/app_state.dart';
import '../../features/home/home.dart';
import '../../features/onboarding/onboarding.dart';
import '../../features/trips/trips.dart';
import '../../features/trips/create_trip.dart';
import '../../features/itinerary/itinerary.dart';
import '../../features/explore/explore.dart';
import '../../features/ai/companion.dart';
import '../../features/profile/profile.dart';
import '../../features/profile/gallery.dart';
import '../../features/trips/trip_tools.dart';
import '../../features/translation/translation.dart';
import '../../shared/components/components.dart';
import '../localization/strings.dart';
import '../../core/network/providers.dart';
import '../../features/connected/connected_shell.dart';
import '../../features/authentication/authentication.dart';
import '../../features/authentication/auth_controller.dart';

class _RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  if (ref.read(environmentProvider).connected) {
    final changes = _RouterRefresh();
    ref.listen(authControllerProvider, (_, _) => changes.refresh());
    ref.onDispose(changes.dispose);
    final connected = GoRouter(
      initialLocation: '/connected',
      refreshListenable: changes,
      redirect: (_, state) =>
          authRedirect(ref.read(authControllerProvider), state.uri),
      routes: [
        GoRoute(path: '/auth', builder: (_, s) => const AuthenticationScreen()),
        GoRoute(path: '/guest', builder: (_, s) => const AuthGuestScreen()),
        GoRoute(path: '/connected', builder: (_, s) => const ConnectedGate()),
      ],
    );
    ref.onDispose(connected.dispose);
    return connected;
  }
  final router = GoRouter(
    initialLocation: ref.read(appStateProvider).onboarded
        ? '/home'
        : '/welcome',
    routes: [
      GoRoute(path: '/welcome', builder: (_, s) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, s) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/trips', builder: (_, s) => const TripsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                builder: (_, s) => const ExploreScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/companion',
                builder: (_, s) => const CompanionScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, s) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/trip/new', builder: (_, s) => const CreateTripScreen()),
      GoRoute(
        path: '/trip/:id',
        builder: (_, s) => ItineraryScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/trip/:id/:tool',
        builder: (_, s) => TripToolsScreen(
          tripId: s.pathParameters['id']!,
          tool: s.pathParameters['tool']!,
        ),
      ),
      GoRoute(
        path: '/place/:id',
        builder: (_, s) => PlaceScreen(place: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/translation',
        builder: (_, s) => const TranslationScreen(),
      ),
      GoRoute(path: '/gallery', builder: (_, s) => const GalleryScreen()),
    ],
    errorBuilder: (c, s) => Scaffold(
      appBar: AppBar(),
      body: EmptyState(
        title: c.t('noResults'),
        body: c.t('trySearch'),
        action: FilledButton(
          onPressed: () => c.go('/home'),
          child: Text(c.t('home')),
        ),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(appStateProvider.select((s) => s.offline));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (offline)
              Notice(
                context.t('offlineBanner'),
                icon: Icons.cloud_off_outlined,
              ),
            Expanded(child: shell),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: context.t('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.work_outline_rounded),
            selectedIcon: const Icon(Icons.work_rounded),
            label: context.t('trips'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            selectedIcon: const Icon(Icons.explore),
            label: context.t('explore'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome),
            label: context.t('ai'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person),
            label: context.t('profile'),
          ),
        ],
      ),
    );
  }
}
