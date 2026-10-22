import 'package:crystal_navigation_bar/crystal_navigation_bar.dart';
import 'package:flutter/material.dart';
import '../../app/localization/strings.dart';

/// Shared frosted navigation for the connected and local shells.
class AnajakBottomBar extends StatelessWidget {
  const AnajakBottomBar({super.key, required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    ('home', Icons.home_outlined, Icons.home_rounded),
    ('trips', Icons.work_outline_rounded, Icons.work_rounded),
    ('explore', Icons.explore_outlined, Icons.explore_rounded),
    ('ai', Icons.auto_awesome_outlined, Icons.auto_awesome),
    ('profile', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final labels = [for (final item in _items) context.t(item.$1)];
    // The crystal package uses fixed-size label boxes. Give accessibility
    // text and narrow screens the extra room of Flutter's native bar.
    if (MediaQuery.textScalerOf(context).scale(12) > 17 ||
        MediaQuery.sizeOf(context).width < 340) {
      return NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onTap,
        destinations: [
          for (var i = 0; i < _items.length; i++)
            NavigationDestination(
              icon: Icon(_items[i].$2),
              selectedIcon: Icon(_items[i].$3),
              label: labels[i],
            ),
        ],
      );
    }
    return SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          // The package defaults labeled bars to 110dp; constrain the chrome
          // while retaining at least 48dp per destination.
          child: SizedBox(
            height: 94,
            child: CrystalNavigationBar(
              currentIndex: index,
              onTap: onTap,
              showLabels: true,
              height: 94,
              marginR: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              paddingR: const EdgeInsets.symmetric(vertical: 6),
              itemPadding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 2,
              ),
              borderRadius: 26,
              borderWidth: 1,
              blurSigma: 28,
              backgroundColor: colors.surface.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? .45
                    : .60,
              ),
              outlineBorderColor: colors.outlineVariant.withValues(alpha: .65),
              selectedItemColor: colors.primary,
              unselectedItemColor: colors.onSurfaceVariant,
              indicatorColor: colors.primary,
              splashBorderRadius: 22,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              items: [
                for (var i = 0; i < _items.length; i++)
                  CrystalNavigationBarItem(
                    icon: _items[i].$3,
                    unselectedIcon: _items[i].$2,
                    label: labels[i],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
