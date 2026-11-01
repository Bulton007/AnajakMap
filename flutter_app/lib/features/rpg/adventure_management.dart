import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../shared/components/visual.dart';
import '../../shared/formatting/travel_dates.dart';
import '../authentication/auth_controller.dart';
import 'adventure_controller.dart';
import 'adventure_repository.dart';
import 'creature_avatar.dart';
import 'creature_catalog.dart';
import 'rpg_layout.dart';
import 'rpg_screen.dart';

/// A live view of the same account controller; no second cache or local rewards.
class AdventureManagement extends ConsumerStatefulWidget {
  const AdventureManagement({
    super.key,
    required this.scope,
    this.initial = 'collection',
  });
  final (String, String) scope;
  final String initial;
  @override
  ConsumerState<AdventureManagement> createState() =>
      _AdventureManagementState();
}

class _AdventureManagementState extends ConsumerState<AdventureManagement> {
  late String section = widget.initial;
  String search = '';
  String t(String en, String km) => rpgText(context, en, km);
  String get language => Localizations.localeOf(context).languageCode;
  String name(String id) => creatureDisplayName(id, language: language);
  String rarity(String value) => switch (value.toLowerCase()) {
    'common' => t('Common', 'ធម្មតា'),
    'rare' => t('Rare', 'កម្រ'),
    'epic' => t('Epic', 'អស្ចារ្យ'),
    _ => value,
  };
  String element(String value) => switch (value.toLowerCase()) {
    'earth' => t('Earth', 'ដី'),
    'fire' => t('Fire', 'ភ្លើង'),
    'water' => t('Water', 'ទឹក'),
    _ => value,
  };
  String habitat(String value) => value == 'temple'
      ? t('Temple', 'ប្រាសាទ')
      : value == 'beach'
      ? t('Coast', 'ឆ្នេរ')
      : value;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (!auth.authenticated || auth.session!.user.id != widget.scope.$1) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(rpgContentPadding),
            child: Text(t('Please sign in again.', 'សូមចូលគណនីម្ដងទៀត។')),
          ),
        ),
      );
    }
    final state = ref.watch(adventureProvider(widget.scope));
    final controller = ref.read(adventureProvider(widget.scope).notifier);
    final data = state.snapshot;
    final labels = {
      'collection': t('Collection', 'បណ្ដុំសត្វ'),
      'party': t('Party', 'ក្រុម'),
      'inventory': t('Inventory', 'សម្ភារៈ'),
      'quests': t('Quests', 'បេសកកម្ម'),
      'achievements': t('Achievements', 'សមិទ្ធផល'),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(labels[section] ?? labels['collection']!),
        actions: [
          IconButton(
            onPressed: state.busy ? null : controller.load,
            icon: const Icon(Icons.refresh),
            tooltip: t('Refresh', 'ផ្ទុកឡើងវិញ'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              key: const Key('rpg-management-list'),
              padding: const EdgeInsets.fromLTRB(
                rpgContentPadding,
                16,
                rpgContentPadding,
                32,
              ),
              children: spacedRpgItems([
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    for (final tab in labels.entries)
                      ChoiceChip(
                        avatar: Icon(featureIcon(tab.key), size: 20),
                        label: Text(tab.value),
                        selected: section == tab.key,
                        onSelected: (_) => setState(() => section = tab.key),
                      ),
                  ],
                ),
                if (state.busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: LinearProgressIndicator(),
                  ),
                if (state.failure != null)
                  _notice(
                    Icons.cloud_off_rounded,
                    state.failure!.message,
                    error: true,
                  ),
                if (state.pending)
                  RpgPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RpgFact(
                          Icons.sync_problem_rounded,
                          t(
                            'Action awaiting confirmation',
                            'សកម្មភាពកំពុងរង់ចាំការបញ្ជាក់',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t(
                            'Retry the same action safely before making another change.',
                            'សូមព្យាយាមសកម្មភាពដដែលម្ដងទៀត មុនធ្វើការផ្លាស់ប្ដូរផ្សេង។',
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: state.busy ? null : controller.retry,
                          icon: const Icon(Icons.sync_rounded),
                          label: Text(
                            t(
                              'Retry pending action',
                              'ព្យាយាមសកម្មភាពដែលរង់ចាំ',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (state.active)
                  _notice(
                    Icons.sports_martial_arts_rounded,
                    t(
                      'Finish or retreat from your battle before changing party, evolving or shopping.',
                      'បញ្ចប់ ឬដកថយពីការប្រយុទ្ធ មុនប្ដូរក្រុម វិវត្ត ឬទិញសម្ភារៈ។',
                    ),
                  ),
                if (data != null) ...[
                  RpgPanel(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.toll_rounded,
                          size: 32,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${integer(data.profile, 'gold')} ${t('game gold', 'មាសហ្គេម')}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.scope.$2 == 'practice'
                                    ? t('Practice progress', 'វឌ្ឍនភាពសាកល្បង')
                                    : t(
                                        'Field progress',
                                        'វឌ្ឍនភាពនៅទីតាំងពិត',
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._section(data, state, controller),
                ] else if (!state.busy)
                  RpgEmptyState(
                    icon: Icons.cloud_off_rounded,
                    message: t(
                      'Adventure data is not available. Refresh to try again.',
                      'មិនមានទិន្នន័យដំណើរផ្សងព្រេង។ សូមផ្ទុកឡើងវិញ។',
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice(IconData icon, String text, {bool error = false}) => RpgPanel(
    color: error
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: error
              ? Theme.of(context).colorScheme.onErrorContainer
              : Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: error
                  ? Theme.of(context).colorScheme.onErrorContainer
                  : null,
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _section(
    AdventureSnapshot data,
    AdventureState state,
    AdventureController controller,
  ) {
    switch (section) {
      case 'party':
        return [
          _notice(
            Icons.groups_rounded,
            t(
              'Choose up to three companions. Each capture keeps its own XP and evolution.',
              'ជ្រើសរើសមិត្តរួមដំណើររហូតដល់បី។ សត្វនីមួយៗរក្សា XP និងការវិវត្តដាច់ដោយឡែក។',
            ),
          ),
          if (data.monsters.isEmpty)
            RpgEmptyState(
              icon: Icons.pets_rounded,
              message: t(
                'Your companions will appear here after capture.',
                'មិត្តរួមដំណើររបស់អ្នកនឹងបង្ហាញនៅទីនេះបន្ទាប់ពីចាប់បាន។',
              ),
            ),
          for (final monster in data.monsters)
            RpgPanel(
              padding: const EdgeInsets.all(8),
              child: CheckboxListTile(
                contentPadding: const EdgeInsets.all(8),
                secondary: CreatureAvatar(
                  speciesId: string(monster, 'speciesId'),
                ),
                title: Text(name(string(monster, 'speciesId'))),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${t('Level', 'កម្រិត')} ${(1 + integer(monster, 'xp') ~/ 100).clamp(1, 50)} · ${t('Evolution', 'វិវត្ត')} ${integer(monster, 'evolution')}/2',
                  ),
                ),
                value: data.party.any(
                  (p) => string(p, 'monsterId') == string(monster, 'id'),
                ),
                onChanged: state.canAct && !state.active
                    ? (selected) =>
                          _changeParty(selected, monster, data, controller)
                    : null,
              ),
            ),
        ];
      case 'inventory':
        return [
          _notice(
            Icons.backpack_rounded,
            t(
              'Buy supplies with game gold. Items are consumed only by confirmed battle actions.',
              'ទិញសម្ភារៈដោយមាសហ្គេម។ សម្ភារៈប្រើប្រាស់តែតាមសកម្មភាពប្រយុទ្ធដែលបានបញ្ជាក់។',
            ),
          ),
          if (data.inventory.isEmpty)
            RpgEmptyState(
              icon: Icons.inventory_2_outlined,
              message: t(
                'No supplies available yet.',
                'មិនទាន់មានសម្ភារៈនៅឡើយ។',
              ),
            ),
          RpgCardGrid(
            children: [
              for (final item in data.inventory)
                _inventory(item, data, state, controller),
            ],
          ),
          if (objects(data.data['transactions']).isNotEmpty) ...[
            _heading(t('Supply history', 'ប្រវត្តិសម្ភារៈ')),
            for (final row in objects(data.data['transactions']))
              RpgPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RpgFact(
                      Icons.receipt_long_rounded,
                      '${string(row, 'asset')} ${integer(row, 'delta') > 0 ? '+' : ''}${integer(row, 'delta')}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      travelDateTime(
                        string(row, 'createdAt'),
                        locale: language,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ];
      case 'quests':
        return [
          _notice(
            Icons.event_repeat_rounded,
            t(
              'Daily quests reset at UTC midnight; weekly quests reset Monday UTC.',
              'បេសកកម្មប្រចាំថ្ងៃកំណត់ឡើងវិញនៅអធ្រាត្រ UTC និងប្រចាំសប្ដាហ៍នៅថ្ងៃចន្ទ UTC។',
            ),
          ),
          if (data.quests.isEmpty)
            RpgEmptyState(
              icon: Icons.explore_outlined,
              message: t(
                'New quests will appear here.',
                'បេសកកម្មថ្មីនឹងបង្ហាញនៅទីនេះ។',
              ),
            ),
          for (final quest in data.quests) _quest(quest, state, controller),
        ];
      case 'achievements':
        return [
          if (data.achievements.isEmpty)
            RpgEmptyState(
              icon: Icons.emoji_events_outlined,
              message: t(
                'Keep exploring to unlock your first achievement.',
                'បន្តរុករកដើម្បីទទួលបានសមិទ្ធផលដំបូង។',
              ),
            ),
          for (final badge in data.achievements)
            _achievement(badge, data, state, controller),
          if (data.exploration.isNotEmpty) ...[
            _heading(t('Your trails', 'ដំណើររបស់អ្នក')),
            for (final destination in data.exploration)
              RpgPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      string(destination, 'name'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 10,
                      children: [
                        RpgFact(
                          Icons.explore_rounded,
                          '${integer(destination, 'successes')} ${t('successful encounters', 'ការជួបសត្វបានជោគជ័យ')}',
                        ),
                        RpgFact(
                          Icons.shield_rounded,
                          '${integer(destination, 'bosses')} ${t('guardians defeated', 'អ្នកការពារដែលបានឈ្នះ')}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
          if (data.history.isNotEmpty) ...[
            _heading(t('Recent adventures', 'ដំណើរថ្មីៗ')),
            for (final battle in data.history)
              RpgPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RpgFact(
                      Icons.history_rounded,
                      '${string(battle, 'kind')} · ${string(battle, 'status')}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      travelDateTime(
                        string(battle, 'completedAt'),
                        locale: language,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ];
      default:
        final visibleSpecies = data.species
            .where(
              (s) =>
                  '${name(string(s, 'id'))} ${creatureDisplayName(string(s, 'id'), language: 'en')} ${creatureDisplayName(string(s, 'id'), language: 'km')} ${string(s, 'id')} ${s['name']} ${element(string(s, 'element'))} ${string(s, 'element')} ${rarity(string(s, 'rarity'))}'
                      .toLowerCase()
                      .contains(search),
            )
            .toList();
        return [
          TextField(
            decoration: InputDecoration(
              labelText: t('Search creatures or elements', 'ស្វែងរកសត្វ ឬធាតុ'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (value) =>
                setState(() => search = value.trim().toLowerCase()),
          ),
          if (visibleSpecies.isEmpty)
            RpgEmptyState(
              icon: Icons.search_off_rounded,
              message: t(
                'No creatures match your search.',
                'គ្មានសត្វត្រូវនឹងការស្វែងរករបស់អ្នក។',
              ),
            ),
          for (final species in visibleSpecies)
            RpgPanel(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                tilePadding: const EdgeInsets.all(16),
                childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                shape: const Border(),
                collapsedShape: const Border(),
                leading: CreatureAvatar(speciesId: string(species, 'id')),
                title: Text(
                  name(string(species, 'id')),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${rarity(string(species, 'rarity'))} · ${element(string(species, 'element'))} · ${habitat(string(species, 'habitat'))}',
                  ),
                ),
                children: spacedRpgItems([
                  Text(creatureLore(string(species, 'id'), language: language)),
                  Wrap(
                    spacing: 16,
                    runSpacing: 10,
                    children: [
                      RpgFact(Icons.favorite_rounded, 'HP ${species['hp']}'),
                      RpgFact(
                        Icons.flash_on_rounded,
                        'ATK ${species['attack']}',
                      ),
                      RpgFact(
                        Icons.shield_rounded,
                        'DEF ${species['defense']}',
                      ),
                      RpgFact(Icons.speed_rounded, 'SPD ${species['speed']}'),
                    ],
                  ),
                  if (!data.monsters.any(
                    (m) => string(m, 'speciesId') == string(species, 'id'),
                  ))
                    Text(t('Not captured yet', 'មិនទាន់ចាប់បានទេ')),
                  for (final monster in data.monsters.where(
                    (m) => string(m, 'speciesId') == string(species, 'id'),
                  ))
                    _monster(monster, data, state, controller),
                ]),
              ),
            ),
        ];
    }
  }

  Widget _heading(String label) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(label, style: Theme.of(context).textTheme.titleLarge),
  );

  Widget _inventory(
    Json item,
    AdventureSnapshot data,
    AdventureState state,
    AdventureController controller,
  ) {
    final kind = string(item, 'item');
    final potion = kind == 'potion';
    final known = potion || kind == 'crystal';
    final price = potion ? 10 : 15;
    final affordable = integer(data.profile, 'gold') >= price;
    return RpgPanel(
      key: Key('rpg-inventory-$kind'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                potion ? Icons.science_rounded : Icons.diamond_rounded,
                size: 36,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${potion
                ? t('Potion', 'ថ្នាំព្យាបាល')
                : kind == 'crystal'
                ? t('Capture crystal', 'គ្រីស្តាល់ចាប់សត្វ')
                : kind} × ${integer(item, 'quantity')}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            potion
                ? t(
                    'Restores up to 30 HP and clears poison.',
                    'ស្ដារ HP រហូតដល់ 30 និងបំបាត់ពុល។',
                  )
                : t(
                    'One capture attempt. Weaken the wild creature first.',
                    'សាកល្បងចាប់មួយដង។ បន្ថយ HP សត្វជាមុន។',
                  ),
          ),
          if (!affordable) ...[
            const SizedBox(height: 12),
            Text(
              t('Earn more game gold', 'រកមាសហ្គេមបន្ថែម'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          const Spacer(),
          FilledButton(
            key: Key('rpg-buy-$kind'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
            onPressed: known && affordable && state.canAct && !state.active
                ? () => controller.manage('inventory/purchase', {
                    'item': kind,
                    'quantity': 1,
                  })
                : null,
            child: Text(
              '${t('Buy one', 'ទិញមួយ')} · $price ${t('gold', 'មាស')}',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quest(Json q, AdventureState state, AdventureController controller) {
    final target = integer(q, 'target').clamp(1, 1000000);
    final progress = integer(q, 'progress').clamp(0, target);
    final claimed = q['claimed'] == true;
    return RpgPanel(
      key: Key('rpg-quest-${string(q, 'id')}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                claimed ? Icons.task_alt_rounded : Icons.explore_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _questTitle(q),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress / target,
            minHeight: 6,
            semanticsLabel: '$progress / $target',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              RpgFact(Icons.flag_rounded, '$progress / $target'),
              RpgFact(Icons.bolt_rounded, '${integer(q, 'xp')} XP'),
              RpgFact(
                Icons.toll_rounded,
                '${integer(q, 'gold')} ${t('gold', 'មាស')}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: Key('rpg-claim-${string(q, 'id')}'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: state.canAct && q['completed'] == true && !claimed
                ? () => controller.claim(string(q, 'id'))
                : null,
            icon: Icon(claimed ? Icons.check_rounded : Icons.redeem_rounded),
            label: Text(
              claimed
                  ? t('Claimed', 'បានទទួល')
                  : t('Claim reward', 'ទទួលរង្វាន់'),
            ),
          ),
        ],
      ),
    );
  }

  String _questTitle(Json quest) => switch (string(quest, 'id')) {
    'first-win' => t('Win your first battle', 'ឈ្នះការប្រយុទ្ធដំបូង'),
    'first-capture' => t(
      'Capture your first companion',
      'ចាប់មិត្តរួមដំណើរដំបូង',
    ),
    'daily-win' => t(
      'Daily: win two battles',
      'ប្រចាំថ្ងៃ៖ ឈ្នះការប្រយុទ្ធពីរដង',
    ),
    'weekly-capture' => t(
      'Weekly: capture three companions',
      'ប្រចាំសប្ដាហ៍៖ ចាប់មិត្តរួមដំណើរបី',
    ),
    'collector' => t('Discover three species', 'ស្វែងរកសត្វបីប្រភេទ'),
    'evolution' => t('Evolve a companion', 'វិវត្តមិត្តរួមដំណើរមួយ'),
    'guardian' => t('Defeat a destination guardian', 'ឈ្នះអ្នកការពារគោលដៅមួយ'),
    _ => string(quest, 'title', string(quest, 'id')),
  };

  Widget _achievement(
    Json badge,
    AdventureSnapshot data,
    AdventureState state,
    AdventureController controller,
  ) {
    final equipped =
        string(data.profile, 'equippedTitle') == string(badge, 'id');
    return RpgPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                badge['unlocked'] == true
                    ? Icons.workspace_premium_rounded
                    : Icons.lock_outline_rounded,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _achievementTitle(badge),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      equipped
                          ? t('Equipped title', 'ងារដែលបានប្រើ')
                          : t('Profile title', 'ងារប្រវត្តិរូប'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: Key('rpg-equip-${string(badge, 'id')}'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed:
                state.canAct &&
                    !state.active &&
                    badge['unlocked'] == true &&
                    !equipped
                ? () => controller.manage('title', {'id': string(badge, 'id')})
                : null,
            icon: Icon(equipped ? Icons.check_rounded : Icons.badge_outlined),
            label: Text(
              equipped ? t('Equipped', 'បានប្រើ') : t('Equip', 'ប្រើ'),
            ),
          ),
        ],
      ),
    );
  }

  String _achievementTitle(Json badge) => switch (string(badge, 'id')) {
    'traveler' => t('Traveler', 'អ្នកធ្វើដំណើរ'),
    'first-win' => t('Trailblazer', 'អ្នកបើកផ្លូវ'),
    'collector' => t('Creature Keeper', 'អ្នកថែរក្សាសត្វវេទមន្ត'),
    'evolution' => t('Awakened', 'អ្នកភ្ញាក់ដឹងខ្លួន'),
    'guardian' => t('Guardian Challenger', 'អ្នកប្រកួតអ្នកការពារ'),
    _ => string(badge, 'title'),
  };

  void _changeParty(
    bool? selected,
    Json monster,
    AdventureSnapshot data,
    AdventureController controller,
  ) {
    final ids = data.party.map((p) => string(p, 'monsterId')).toList();
    final id = string(monster, 'id');
    if (selected == true) {
      if (ids.length >= 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                'Party is full: remove a companion first.',
                'ក្រុមពេញហើយ៖ ដកសត្វមួយជាមុន។',
              ),
            ),
          ),
        );
        return;
      }
      ids.add(id);
    } else {
      if (ids.length == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                'Keep at least one companion in your party.',
                'រក្សាសត្វយ៉ាងហោចណាស់មួយក្នុងក្រុម។',
              ),
            ),
          ),
        );
        return;
      }
      ids.remove(id);
    }
    controller.manage('party', {'monsterIds': ids});
  }

  Widget _monster(
    Json monster,
    AdventureSnapshot data,
    AdventureState state,
    AdventureController controller,
  ) {
    final stage = integer(monster, 'evolution');
    final level = (1 + integer(monster, 'xp') ~/ 100).clamp(1, 50);
    final requiredLevel = stage == 0 ? 4 : 8;
    final stats = object(monster['stats']);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: spacedRpgItems([
            Text(
              '${t('Level', 'កម្រិត')} $level · ${integer(monster, 'xp')} XP · ${t('Evolution', 'វិវត្ត')} $stage/2',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (stats.isNotEmpty)
              Wrap(
                spacing: 16,
                runSpacing: 10,
                children: [
                  RpgFact(Icons.favorite_rounded, 'HP ${integer(stats, 'hp')}'),
                  RpgFact(
                    Icons.flash_on_rounded,
                    'ATK ${integer(stats, 'attack')}',
                  ),
                  RpgFact(
                    Icons.shield_rounded,
                    'DEF ${integer(stats, 'defense')}',
                  ),
                  RpgFact(
                    Icons.speed_rounded,
                    'SPD ${integer(stats, 'speed')}',
                  ),
                ],
              ),
            if (monster['abilities'] is List)
              Text(
                '${t('Abilities', 'សមត្ថភាព')}: ${(monster['abilities'] as List).join(', ')}',
              ),
            if (monster['passive'] is String) Text(string(monster, 'passive')),
            if (stage < 2)
              OutlinedButton.icon(
                key: Key('rpg-evolve-${string(monster, 'id')}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed:
                    state.canAct &&
                        !state.active &&
                        level >= requiredLevel &&
                        integer(data.profile, 'gold') >= 75 * (stage + 1)
                    ? () => controller.manage(
                        'monsters/${string(monster, 'id')}/evolve',
                        {'stage': stage},
                      )
                    : null,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(
                  '${t('Evolve', 'វិវត្ត')} · Lv $requiredLevel · ${75 * (stage + 1)} ${t('gold', 'មាស')}',
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
