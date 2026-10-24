import 'creature_avatar.dart';
import 'dart:async';
import 'encounter_policy.dart';
import '../../shared/components/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../authentication/auth_controller.dart';
import '../maps/open_map_screen.dart';
import 'adventure_controller.dart';
import 'adventure_repository.dart';
import 'adventure_management.dart';
import 'battle_scene.dart';
import 'encounter_countdown.dart';
import '../../shared/formatting/travel_dates.dart';
import 'rpg_game.dart';
import 'rpg_screen.dart';

class AdventureScreen extends ConsumerStatefulWidget {
  const AdventureScreen({super.key, this.destinationId});
  final String? destinationId;
  @override
  ConsumerState<AdventureScreen> createState() => _AdventureScreenState();
}

class _AdventureScreenState extends ConsumerState<AdventureScreen> {
  String realm = 'field';
  String? destination, lead;
  bool safe = false;
  bool boss = false;
  bool discover = false, awaitingFight = false;
  Timer? discoveryTimer;
  final encounters = EncounterPolicy(
    probability:
        const int.fromEnvironment('RPG_ENCOUNTER_PERCENT', defaultValue: 25) /
        100,
    cooldown: const Duration(
      seconds: int.fromEnvironment(
        'RPG_ENCOUNTER_COOLDOWN_SECONDS',
        defaultValue: 300,
      ),
    ),
  );
  String t(String en, String km) => rpgText(context, en, km);
  @override
  void initState() {
    super.initState();
    destination = widget.destinationId;
    discoveryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => checkEncounter(),
    );
  }

  Future<void> checkEncounter() async {
    if (!mounted ||
        !discover ||
        !safe ||
        realm != 'field' ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        ModalRoute.of(context)?.isCurrent != true ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    final auth = ref.read(authControllerProvider);
    if (!auth.authenticated || destination == null || lead == null) return;
    final scope = (auth.session!.user.id, realm);
    final state = ref.read(adventureProvider(scope));
    if (!encounters.roll(
      DateTime.now(),
      eligible: state.canAct && !state.active,
    )) {
      return;
    }
    setState(() => awaitingFight = true);
    await ref
        .read(adventureProvider(scope).notifier)
        .start(destination!, lead!, safe);
  }

  @override
  void dispose() {
    discoveryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final connected = ref.watch(environmentProvider).connected;
    if (!connected || !auth.authenticated) {
      return Scaffold(
        appBar: AppBar(title: Text(t('Creature trails', 'ដំណើរសត្វវេទមន្ត'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t(
                    'Sign in to the connected app to save an account adventure.',
                    'ចូលគណនីក្នុងកម្មវិធីដែលភ្ជាប់ម៉ាស៊ីនមេ ដើម្បីរក្សាទុកដំណើរផ្សងព្រេង។',
                  ),
                ),
                if (connected)
                  FilledButton(
                    onPressed: () => context.go('/auth?from=%2Fadventure'),
                    child: Text(t('Sign in', 'ចូលគណនី')),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final provider = adventureProvider((auth.session!.user.id, realm));
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final snapshot = state.snapshot;
    final selected = state.world
        .where((d) => string(d, 'id') == destination)
        .firstOrNull;
    final owned = (snapshot?.monsters ?? [])
        .where(
          (m) =>
              snapshot?.data.containsKey('party') != true ||
              snapshot!.party.any(
                (p) => string(p, 'monsterId') == string(m, 'id'),
              ),
        )
        .toList();
    final monsterId = owned.any((m) => string(m, 'id') == lead)
        ? lead
        : owned.firstOrNull?['ID']?.toString() ??
              (owned.isEmpty ? null : string(owned.first, 'id'));
    final eligible =
        selected != null &&
        (realm == 'practice' ||
            (integer(selected, 'approved') == 1 &&
                integer(selected, 'accessible') == 1));
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Creature trails', 'ដំណើរសត្វវេទមន្ត')),
        actions: [
          IconButton(
            tooltip: t('Refresh from server', 'ផ្ទុកពីម៉ាស៊ីនមេម្ដងទៀត'),
            onPressed: state.busy ? null : controller.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                VisualHero(
                  title: t(
                    'A new trail. A new companion.',
                    'ដំណើរថ្មី។ មិត្តរួមដំណើរថ្មី។',
                  ),
                  caption: t('CREATURE TRAILS', 'ដំណើរសត្វវេទមន្ត'),
                ),
                ExpansionTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(t('About this adventure', 'អំពីដំណើរនេះ')),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        t(
                          'Temporary procedural 3D artwork. Game gold has no cash value; travel redemption is unavailable.',
                          'រូបភាព 3D បណ្ដោះអាសន្ន។ មាសហ្គេមគ្មានតម្លៃជាប្រាក់ និងមិនអាចប្ដូររង្វាន់ធ្វើដំណើរបានទេ។',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(t('Field adventure', 'ផ្សងព្រេងនៅទីតាំងពិត')),
                      selected: realm == 'field',
                      onSelected: state.busy || state.pending
                          ? null
                          : (_) => setState(() {
                              realm = 'field';
                              safe = false;
                              lead = null;
                            }),
                    ),
                    ChoiceChip(
                      label: Text(t('Server practice', 'សាកល្បងលើម៉ាស៊ីនមេ')),
                      selected: realm == 'practice',
                      onSelected:
                          state.busy ||
                              state.pending ||
                              state.capabilities['practiceEnabled'] != true
                          ? null
                          : (_) => setState(() {
                              realm = 'practice';
                              safe = false;
                              lead = null;
                            }),
                    ),
                  ],
                ),
                if (realm == 'practice')
                  _notice(
                    t(
                      'SIMULATION • No GPS required. Separate test XP, gold and collection; never transferred to field rewards.',
                      'សាកល្បង • មិនត្រូវការ GPS។ XP មាស និងសត្វសាកល្បងដាច់ដោយឡែក មិនផ្ទេរទៅរង្វាន់ទីតាំងពិតទេ។',
                    ),
                  ),
                if (state.busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (state.failure != null)
                  _notice(
                    '${t('Could not sync adventure.', 'មិនអាចធ្វើសមកាលកម្មបានទេ។')} ${state.failure!.message}',
                  ),
                if (state.retryAt != null)
                  Text(
                    '${t('Retry after', 'ព្យាយាមក្រោយ')} ${state.retryAt!.toLocal()}',
                  ),
                if (state.pending) ...[
                  Text(
                    t(
                      'The result is not confirmed. Retry the same request safely before another action.',
                      'មិនទាន់បញ្ជាក់លទ្ធផល។ ព្យាយាមសំណើដដែលម្ដងទៀត មុនធ្វើសកម្មភាពផ្សេង។',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: state.busy ? null : controller.retry,
                    child: Text(
                      t('Retry pending action', 'ព្យាយាមសកម្មភាពដែលរង់ចាំ'),
                    ),
                  ),
                ] else if (state.needsRefresh)
                  OutlinedButton(
                    onPressed: state.busy ? null : controller.load,
                    child: Text(
                      t('Refresh adventure', 'ផ្ទុកដំណើរផ្សងព្រេងម្ដងទៀត'),
                    ),
                  ),
                if (snapshot != null) ...[
                  VisualActions(
                    children: [
                      for (final entry in {
                        'collection': t('Collection', 'បណ្ដុំសត្វ'),
                        'party': t('Party', 'ក្រុម'),
                        'inventory': t('Inventory', 'សម្ភារៈ'),
                        'quests': t('Quests', 'បេសកកម្ម'),
                        'achievements': t('Achievements', 'សមិទ្ធផល'),
                      }.entries)
                        VisualAction(
                          compact: true,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AdventureManagement(
                                scope: (auth.session!.user.id, realm),
                                initial: entry.key,
                              ),
                            ),
                          ),
                          icon: featureIcon(entry.key),
                          label: entry.value,
                        ),
                    ],
                  ),
                  Text(
                    '${t('Title', 'ងារ')}: ${string(snapshot.profile, 'equippedTitle', 'traveler')}',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.stars_rounded, size: 20),
                        label: Text(
                          '${t('Level', 'កម្រិត')} ${(1 + integer(snapshot.profile, 'xp') ~/ 100).clamp(1, 50)}',
                        ),
                      ),
                      Chip(
                        avatar: const Icon(Icons.bolt_rounded, size: 20),
                        label: Text('${integer(snapshot.profile, 'xp')} XP'),
                      ),
                      Chip(
                        label: Text(
                          '${integer(snapshot.profile, 'gold')} ${t('gold', 'មាស')}',
                        ),
                      ),
                    ],
                  ),
                  if (state.session != null)
                    if (!state.expired)
                      _battle(state, snapshot, controller)
                    else
                      _notice(
                        t(
                          'Encounter expired. Refresh to continue; no reward is granted for expiry.',
                          'ការជួបនេះផុតកំណត់ហើយ។ ផ្ទុកឡើងវិញដើម្បីបន្ត។',
                        ),
                      ),
                  _heading(t('Choose your destination', 'ជ្រើសរើសគោលដៅ')),
                  Text(
                    t(
                      'Map pins are destination information, not live monster locations.',
                      'ម្ជុលផែនទីជាព័ត៌មានគោលដៅ មិនមែនទីតាំងសត្វផ្ទាល់ទេ។',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: Text(
                      t('Choose on OpenStreetMap', 'ជ្រើសរើសលើ OpenStreetMap'),
                    ),
                    onPressed: state.busy || state.pending || state.active
                        ? null
                        : () async {
                            final id = await Navigator.of(context).push<String>(
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(
                                    title: Text(
                                      t('Destination map', 'ផែនទីគោលដៅ'),
                                    ),
                                  ),
                                  body: SafeArea(
                                    child: TravelOpenMap(
                                      places: [
                                        for (final d in state.world)
                                          MapPlace(
                                            string(d, 'id'),
                                            string(d, 'name'),
                                            (field(d, 'latitude') as num)
                                                .toDouble(),
                                            (field(d, 'longitude') as num)
                                                .toDouble(),
                                          ),
                                      ],
                                      onPlaceSelected: (p) =>
                                          Navigator.of(context).pop(p.id),
                                    ),
                                  ),
                                ),
                              ),
                            );
                            if (mounted && id != null) {
                              setState(() {
                                destination = id;
                                safe = false;
                              });
                            }
                          },
                  ),
                  for (final d in state.world)
                    Card(
                      child: ListTile(
                        selected: string(d, 'id') == destination,
                        leading: Icon(
                          string(d, 'habitat') == 'beach'
                              ? Icons.beach_access_outlined
                              : Icons.temple_buddhist_outlined,
                        ),
                        title: Text(string(d, 'name')),
                        subtitle: Text(
                          '${string(d, 'habitat')} • ${t('Level', 'កម្រិត')} ${integer(d, 'minLevel')} • ${integer(d, 'radiusM')} m\n${integer(d, 'approved') == 1 && integer(d, 'accessible') == 1 ? t('Reviewed location', 'ទីតាំងបានពិនិត្យ') : t('Test fixture • field play unavailable', 'ទីតាំងសាកល្បង • មិនអាចលេងនៅទីតាំងពិតបានទេ')}',
                        ),
                        trailing: string(d, 'id') == destination
                            ? const Icon(Icons.check_circle)
                            : null,
                        onTap: state.busy || state.pending || state.active
                            ? null
                            : () => setState(() {
                                destination = string(d, 'id');
                                safe = false;
                              }),
                      ),
                    ),
                  if (state.world.isEmpty)
                    Text(
                      t(
                        'No destinations are configured.',
                        'មិនទាន់មានគោលដៅដែលបានកំណត់ទេ។',
                      ),
                    ),
                  if (selected != null) ...[
                    Text(
                      '${t('Recommended level', 'កម្រិតណែនាំ')}: ${integer(selected, 'recommendedLevel')} • ${t('Enemy level', 'កម្រិតសត្រូវ')}: ${integer(selected, 'enemyLevelMin')}–${integer(selected, 'enemyLevelMax')}',
                    ),
                    for (final progress in snapshot.exploration.where(
                      (p) => string(p, 'id') == destination,
                    ))
                      Text(
                        '${t('Exploration', 'ការរុករក')}: ${integer(progress, 'successes')} / ${integer(selected, 'bossUnlockWins')} • ${t('Guardians defeated', 'អ្នកការពារដែលបានឈ្នះ')}: ${integer(progress, 'bosses')}',
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: boss,
                      onChanged: state.canAct && !state.active
                          ? (v) => setState(() => boss = v ?? false)
                          : null,
                      title: Text(
                        t('Guardian challenge', 'ប្រកួតជាមួយអ្នកការពារ'),
                      ),
                      subtitle: Text(
                        '${t('Requires successful encounters here', 'ត្រូវការជួបសត្វបានជោគជ័យនៅទីនេះ')}: ${integer(selected, 'bossUnlockWins')} • Lv ${integer(selected, 'bossLevel')}',
                      ),
                    ),
                    Text(
                      '${t('Encounter rules', 'ច្បាប់ជួបសត្វ')}: ${integer(selected, 'cooldownSeconds')}s • ${integer(selected, 'dailyLimit')}/UTC day',
                    ),
                    Text(
                      '${t('Available species', 'ប្រភេទសត្វដែលអាចជួប')}: ${objects(selected['spawnRules']).map((rule) => '${string(snapshot.speciesFor(string(rule, 'speciesId')), 'name')} (${t('weight', 'ទម្ងន់')} ${integer(rule, 'weight')})').join(', ')}',
                    ),
                  ],
                  _heading(t('Your companion', 'មិត្តរួមដំណើររបស់អ្នក')),
                  for (final m in owned)
                    Card(
                      child: ListTile(
                        leading: CreatureAvatar(
                          speciesId: string(m, 'speciesId'),
                        ),
                        title: Text(
                          string(
                            snapshot.speciesFor(string(m, 'speciesId')),
                            'name',
                            string(m, 'speciesId'),
                          ),
                        ),
                        subtitle: Text(
                          '${t('Level', 'កម្រិត')} ${(1 + integer(m, 'xp') ~/ 100).clamp(1, 50)} • ${integer(m, 'xp')} XP • ${t('Variation', 'លក្ខណៈពិសេស')} ${integer(m, 'variation')}',
                        ),
                        trailing: Icon(
                          string(m, 'id') == monsterId
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                        ),
                        onTap: state.canAct && !state.active
                            ? () => setState(() => lead = string(m, 'id'))
                            : null,
                      ),
                    ),
                  CheckboxListTile(
                    key: const Key('adventure-safety-consent'),
                    contentPadding: EdgeInsets.zero,
                    value: safe,
                    onChanged: state.canAct && !state.active
                        ? (value) => setState(() => safe = value ?? false)
                        : null,
                    title: Text(
                      t(
                        'I am stationary in a safe, permitted area. I will not play in traffic or restricted places.',
                        'ខ្ញុំឈប់នៅតំបន់សុវត្ថិភាពដែលអនុញ្ញាត។ ខ្ញុំមិនលេងនៅផ្លូវចរាចរណ៍ ឬទីតាំងហាមឃាត់ទេ។',
                      ),
                    ),
                  ),
                  if (realm == 'field')
                    SwitchListTile(
                      value: discover,
                      onChanged:
                          safe &&
                              eligible &&
                              monsterId != null &&
                              state.canAct &&
                              !state.active
                          ? (value) => setState(() {
                              discover = value;
                              lead = monsterId;
                            })
                          : null,
                      secondary: const Icon(Icons.radar),
                      title: Text(
                        t('Discover random creatures', 'ស្វែងរកសត្វដោយចៃដន្យ'),
                      ),
                      subtitle: Text(
                        t(
                          'Optional checks while this page is open and you remain safely stationary. The server verifies location and limits encounters.',
                          'ពិនិត្យនៅពេលទំព័រនេះបើក ហើយអ្នកនៅទីតាំងមានសុវត្ថិភាព។ ម៉ាស៊ីនមេផ្ទៀងផ្ទាត់ទីតាំង និងកម្រិតការជួប។',
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: const Icon(Icons.explore_outlined),
                    onPressed:
                        state.canAct &&
                            !state.active &&
                            safe &&
                            eligible &&
                            monsterId != null
                        ? () => controller.start(
                            destination!,
                            monsterId,
                            safe,
                            boss: boss,
                          )
                        : null,
                    label: Text(
                      realm == 'practice'
                          ? t('Start test encounter', 'ចាប់ផ្ដើមជួបសត្វសាកល្បង')
                          : t(
                              'Check GPS & start encounter',
                              'ពិនិត្យ GPS និងចាប់ផ្ដើមជួបសត្វ',
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.task_alt_rounded, size: 32),
                      title: Text(t('Quest journal', 'កំណត់ហេតុបេសកកម្ម')),
                      subtitle: Text(
                        '${snapshot.quests.where((q) => q['completed'] == true && q['claimed'] != true).length} ${t('rewards ready', 'រង្វាន់រួចរាល់')}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AdventureManagement(
                            scope: (auth.session!.user.id, realm),
                            initial: 'quests',
                          ),
                        ),
                      ),
                    ),
                  ),
                  ExpansionTile(
                    title: Text(
                      t(
                        'Creature guide · not nearby encounters',
                        'បញ្ជីសត្វ · មិនមែនការជួបនៅជិតទេ',
                      ),
                    ),
                    leading: const Icon(Icons.menu_book_outlined),
                    children: [
                      VisualActions(
                        children: [
                          for (final s in snapshot.species)
                            Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AdventureManagement(
                                      scope: (auth.session!.user.id, realm),
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    children: [
                                      if (creatures.any((c) => c.id == s['id']))
                                        SizedBox(
                                          height: 110,
                                          child: CreaturePortrait(
                                            creature: creatures.firstWhere(
                                              (c) => c.id == s['id'],
                                            ),
                                          ),
                                        ),
                                      Text(
                                        string(s, 'name'),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      Text(
                                        string(s, 'rarity'),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: Text(t('Reward history', 'ប្រវត្តិរង្វាន់')),
                    leading: const Icon(Icons.history),
                    children: [
                      if (snapshot.ledger.isEmpty)
                        Text(
                          t(
                            'No rewards yet. Completed battles and claimed quests appear here.',
                            'មិនទាន់មានរង្វាន់ទេ។ ការប្រយុទ្ធ និងរង្វាន់បេសកកម្មនឹងបង្ហាញនៅទីនេះ។',
                          ),
                        ),
                      for (final r in snapshot.ledger)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(
                            '${integer(r, 'xp')} XP • ${integer(r, 'gold')} ${t('gold', 'មាស')}',
                          ),
                          subtitle: Text(
                            '${string(r, 'kind')} • ${travelDateTime(string(r, 'createdAt'), locale: Localizations.localeOf(context).languageCode)}',
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
  Widget _notice(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Semantics(liveRegion: true, child: Text(text)),
  );
  Widget _battle(
    AdventureState state,
    AdventureSnapshot snapshot,
    AdventureController controller,
  ) {
    final session = state.session!;
    final battle = object(session['battle']);
    final enemy = object(battle['enemy']), ally = object(battle['ally']);
    final species = string(enemy, 'speciesId');
    final portrait = creatures.where((c) => c.id == species).firstOrNull;
    final labels = {
      'strike': t('Strike', 'វាយ'),
      'magic': t('Magic', 'វេទមន្ត'),
      'burst': t('Burst · Lv 3', 'វាយខ្លាំង · Lv 3'),
      'guard': t('Guard', 'ការពារ'),
      'heal': t('Heal', 'ព្យាបាល'),
      'capture': t('Capture', 'ចាប់'),
      'retreat': t('Retreat', 'ដកថយ'),
    };
    if (state.active && awaitingFight) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                t('A creature appeared!', 'សត្វមួយបានបង្ហាញខ្លួន!'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              BattleScene(key: ValueKey(session['id']), session: session),
              Text(
                '${string(snapshot.speciesFor(species), 'name', species)} · Lv ${integer(enemy, 'level')}',
              ),
              EncounterCountdown(expiresAt: string(session, 'expiresAt')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: state.canAct
                        ? () => setState(() => awaitingFight = false)
                        : null,
                    icon: const Icon(Icons.sports_martial_arts),
                    label: Text(t('Fight', 'ប្រយុទ្ធ')),
                  ),
                  OutlinedButton(
                    onPressed: state.canAct
                        ? () => controller.move('retreat')
                        : null,
                    child: Text(t('Ignore', 'មិនអើពើ')),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${string(snapshot.speciesFor(species), 'name', species)} • ${t('Level', 'កម្រិត')} ${integer(enemy, 'level')}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            BattleScene(key: ValueKey(session['id']), session: session),
            if (portrait != null)
              LinearProgressIndicator(
                value:
                    (integer(enemy, 'hp') /
                            (integer(snapshot.speciesFor(species), 'hp') +
                                    integer(enemy, 'level') * 4 +
                                    integer(enemy, 'variation') +
                                    integer(enemy, 'evolution') * 12)
                                .clamp(1, 99999))
                        .clamp(0, 1),
              ),
            Semantics(
              liveRegion: true,
              child: Text(
                '${t('Enemy', 'សត្រូវ')}: ${integer(enemy, 'hp')} HP\n${t('Companion', 'មិត្តរួមដំណើរ')}: ${integer(ally, 'hp')} HP • ${integer(ally, 'energy')} ${t('energy', 'ថាមពល')} • ${integer(ally, 'poison')} ${t('poison turns', 'វេនពុល')}',
              ),
            ),
            Text(
              '${integer(battle, 'crystals')} ${t('capture crystals', 'គ្រីស្តាល់ចាប់សត្វ')} • ${integer(battle, 'potions')} ${t('potions', 'ថ្នាំព្យាបាល')}',
            ),
            if (state.active) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final move in labels.entries)
                    OutlinedButton.icon(
                      icon: Icon(switch (move.key) {
                        'strike' => Icons.sports_martial_arts,
                        'magic' => Icons.auto_awesome,
                        'burst' => Icons.bolt,
                        'guard' => Icons.shield_outlined,
                        'heal' => Icons.healing,
                        'capture' => Icons.diamond_outlined,
                        _ => Icons.directions_run,
                      }),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(100, 48),
                      ),
                      onPressed:
                          state.canAct &&
                              (integer(ally, 'hp') > 0 ||
                                  move.key == 'retreat') &&
                              !(move.key == 'burst' &&
                                  (integer(ally, 'level') < 3 ||
                                      integer(ally, 'energy') < 2)) &&
                              !(move.key == 'magic' &&
                                  integer(ally, 'energy') == 0) &&
                              !(move.key == 'heal' &&
                                  integer(battle, 'potions') == 0) &&
                              !(move.key == 'capture' &&
                                  (integer(battle, 'crystals') == 0 ||
                                      battle['boss'] == true))
                          ? () => controller.move(move.key)
                          : null,
                      label: Text(move.value),
                    ),
                ],
              ),
              for (final member in objects(
                session['party'],
              ).where((m) => m['id'] != session['activeMonsterId']))
                OutlinedButton.icon(
                  onPressed:
                      state.canAct &&
                          integer(object(member['fighter']), 'hp') > 0
                      ? () => controller.move(
                          'switch',
                          monsterId: string(member, 'id'),
                        )
                      : null,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(
                    '${t('Switch', 'ប្ដូរ')} ${string(object(member['fighter']), 'speciesId')} • ${integer(object(member['fighter']), 'hp')} HP',
                  ),
                ),
            ] else
              _notice(
                '${t('Encounter result', 'លទ្ធផលជួបសត្វ')}: ${session['status']}. ${t('Rewards shown below are confirmed by the server.', 'រង្វាន់ខាងក្រោមត្រូវបានបញ្ជាក់ដោយម៉ាស៊ីនមេ។')}',
              ),
            ExpansionTile(
              title: Text(t('Battle log', 'កំណត់ហេតុប្រយុទ្ធ')),
              children: [
                for (final entry in battle['log'] as List? ?? [])
                  Text('• $entry'),
              ],
            ),
            if (state.active)
              EncounterCountdown(expiresAt: string(session, 'expiresAt')),
          ],
        ),
      ),
    );
  }
}
