import 'creature_avatar.dart';
import '../../shared/components/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../authentication/auth_controller.dart';
import 'adventure_controller.dart';
import 'adventure_repository.dart';
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
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (!auth.authenticated || auth.session!.user.id != widget.scope.$1) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(t('Please sign in again.', 'សូមចូលគណនីម្ដងទៀត។')),
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
        title: Text(labels[section]!),
        actions: [
          IconButton(
            onPressed: state.busy ? null : controller.load,
            icon: const Icon(Icons.refresh),
            tooltip: t('Refresh', 'ផ្ទុកឡើងវិញ'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
            if (state.busy) const LinearProgressIndicator(),
            if (state.failure != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(state.failure!.message),
              ),
            if (state.pending)
              OutlinedButton(
                onPressed: state.busy ? null : controller.retry,
                child: Text(
                  t('Retry pending action', 'ព្យាយាមសកម្មភាពដែលរង់ចាំ'),
                ),
              ),
            if (state.active)
              Text(
                t(
                  'Finish or retreat from your battle before changing party, evolving or shopping.',
                  'បញ្ចប់ ឬដកថយពីការប្រយុទ្ធ មុនប្ដូរក្រុម វិវត្ត ឬទិញសម្ភារៈ។',
                ),
              ),
            if (data != null) ...[
              Text(
                '${integer(data.profile, 'gold')} ${t('game gold', 'មាសហ្គេម')} • ${widget.scope.$2}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (section == 'collection') ...[
                TextField(
                  decoration: InputDecoration(
                    labelText: t(
                      'Search species or element',
                      'ស្វែងរកប្រភេទ ឬធាតុ',
                    ),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (value) =>
                      setState(() => search = value.toLowerCase()),
                ),
                for (final species in data.species.where(
                  (s) => '${s['name']} ${s['element']} ${s['rarity']}'
                      .toLowerCase()
                      .contains(search),
                ))
                  ExpansionTile(
                    leading: CreatureAvatar(speciesId: string(species, 'id')),
                    title: Text(string(species, 'name')),
                    subtitle: Text(
                      '${species['rarity']} • ${species['element']} • ${species['habitat']}',
                    ),
                    children: [
                      Text(
                        'HP ${species['hp']} / ATK ${species['attack']} / DEF ${species['defense']} / SPD ${species['speed']}',
                      ),
                      Text(
                        t(
                          'Magic at level 1 • Burst at level 3. Evolution increases health, attack, defense and guard.',
                          'វេទមន្តនៅកម្រិត 1 • វាយខ្លាំងនៅកម្រិត 3។ ការវិវត្តបង្កើនសុខភាព និងកម្លាំង។',
                        ),
                      ),
                      if (!data.monsters.any(
                        (m) => string(m, 'speciesId') == species['id'],
                      ))
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            t('Not captured yet', 'មិនទាន់ចាប់បានទេ'),
                          ),
                        ),
                      for (final monster in data.monsters.where(
                        (m) => string(m, 'speciesId') == species['id'],
                      ))
                        _monster(monster, data, state, controller),
                    ],
                  ),
              ],
              if (section == 'party') ...[
                Text(
                  t(
                    'Choose up to three companions. Each captured duplicate has its own XP, variation and evolution.',
                    'ជ្រើសរើសមិត្តរួមដំណើររហូតដល់បី។ សត្វនីមួយៗមាន XP និងការវិវត្តដាច់ដោយឡែក។',
                  ),
                ),
                for (final monster in data.monsters)
                  CheckboxListTile(
                    title: Text(
                      string(
                        data.speciesFor(string(monster, 'speciesId')),
                        'name',
                      ),
                    ),
                    subtitle: Text(
                      '${string(monster, 'id').substring(0, string(monster, 'id').length.clamp(0, 8))} • Lv ${(1 + integer(monster, 'xp') ~/ 100).clamp(1, 50)} • E${integer(monster, 'evolution')}',
                    ),
                    value: data.party.any(
                      (p) => string(p, 'monsterId') == string(monster, 'id'),
                    ),
                    onChanged: state.canAct && !state.active
                        ? (selected) {
                            final ids = data.party
                                .map((p) => string(p, 'monsterId'))
                                .toList();
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
                        : null,
                  ),
              ],
              if (section == 'inventory') ...[
                Text(
                  t(
                    'Purchases use game gold only. Items persist and are consumed by server-confirmed battle actions.',
                    'ការទិញប្រើតែមាសហ្គេម។ សម្ភារៈរក្សាទុក និងប្រើប្រាស់តាមលទ្ធផលម៉ាស៊ីនមេ។',
                  ),
                ),
                for (final item in data.inventory)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            string(item, 'item') == 'potion'
                                ? Icons.science_rounded
                                : Icons.diamond_rounded,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${string(item, 'item')} × ${integer(item, 'quantity')}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            string(item, 'item') == 'potion'
                                ? t(
                                    'Restores up to 30 HP and clears poison.',
                                    'ស្ដារ HP រហូតដល់ 30 និងបំបាត់ពុល។',
                                  )
                                : t(
                                    'One capture attempt. Weaken the wild creature first.',
                                    'សាកល្បងចាប់មួយដង។ បន្ថយ HP សត្វជាមុន។',
                                  ),
                          ),
                          FilledButton(
                            onPressed: state.canAct && !state.active
                                ? () =>
                                      controller.manage('inventory/purchase', {
                                        'item': string(item, 'item'),
                                        'quantity': 1,
                                      })
                                : null,
                            child: Text(
                              '${t('Buy one', 'ទិញមួយ')} • ${string(item, 'item') == 'potion' ? 10 : 15} ${t('gold', 'មាស')}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final row in objects(data.data['transactions']))
                  ListTile(
                    title: Text(
                      '${string(row, 'asset')} ${integer(row, 'delta') > 0 ? '+' : ''}${integer(row, 'delta')}',
                    ),
                    subtitle: Text(
                      '${string(row, 'sourceId')}\n${string(row, 'createdAt')}',
                    ),
                  ),
              ],
              if (section == 'quests') ...[
                Text(
                  t(
                    'Daily quests reset at UTC midnight; weekly quests reset Monday UTC.',
                    'បេសកកម្មប្រចាំថ្ងៃកំណត់ឡើងវិញនៅអធ្រាត្រ UTC និងប្រចាំសប្ដាហ៍នៅថ្ងៃចន្ទ UTC។',
                  ),
                ),
                for (final q in data.quests)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            string(q, 'title', string(q, 'id')),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${q['progress']}/${q['target']} • ${q['xp']} XP • ${q['gold']} ${t('gold', 'មាស')}',
                          ),
                          TextButton(
                            onPressed:
                                state.canAct &&
                                    q['completed'] == true &&
                                    q['claimed'] != true
                                ? () => controller.claim(q['id'])
                                : null,
                            child: Text(
                              q['claimed'] == true
                                  ? t('Claimed', 'បានទទួល')
                                  : t('Claim reward', 'ទទួលរង្វាន់'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (section == 'achievements') ...[
                for (final badge in data.achievements)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        badge['unlocked'] == true
                            ? Icons.workspace_premium
                            : Icons.lock_outline,
                      ),
                      title: Text(string(badge, 'title')),
                      subtitle: Text(
                        string(data.profile, 'equippedTitle') == badge['id']
                            ? t('Equipped title', 'ងារដែលបានប្រើ')
                            : t('Profile title', 'ងារប្រវត្តិរូប'),
                      ),
                      trailing: TextButton(
                        onPressed:
                            state.canAct &&
                                !state.active &&
                                badge['unlocked'] == true
                            ? () => controller.manage('title', {
                                'id': badge['id'],
                              })
                            : null,
                        child: Text(t('Equip', 'ប្រើ')),
                      ),
                    ),
                  ),
                for (final destination in data.exploration)
                  ListTile(
                    title: Text(string(destination, 'name')),
                    subtitle: Text(
                      '${integer(destination, 'successes')} ${t('successful encounters', 'ការជួបសត្វបានជោគជ័យ')} • ${integer(destination, 'bosses')} ${t('guardians defeated', 'អ្នកការពារដែលបានឈ្នះ')}',
                    ),
                  ),
                for (final battle in data.history)
                  ListTile(
                    title: Text(
                      '${string(battle, 'kind')} • ${string(battle, 'status')}',
                    ),
                    subtitle: Text(string(battle, 'completedAt')),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _monster(
    Json monster,
    AdventureSnapshot data,
    AdventureState state,
    AdventureController controller,
  ) {
    final stage = integer(monster, 'evolution'),
        level = (1 + integer(monster, 'xp') ~/ 100).clamp(1, 50),
        requiredLevel = stage == 0 ? 4 : 8;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lv $level • ${integer(monster, 'xp')} XP • ${t('Evolution', 'វិវត្ត')} $stage/2 • ${t('Variation', 'លក្ខណៈពិសេស')} ${integer(monster, 'variation')}',
          ),
          if (monster['stats'] is Map)
            Text(
              'HP ${object(monster['stats'])['hp']} • ATK ${object(monster['stats'])['attack']} • DEF ${object(monster['stats'])['defense']} • SPD ${object(monster['stats'])['speed']}',
            ),
          if (monster['abilities'] is List)
            Text(
              '${t('Abilities', 'សមត្ថភាព')}: ${(monster['abilities'] as List).join(', ')}',
            ),
          if (monster['passive'] is String) Text(string(monster, 'passive')),
          Text(
            '${t('Acquired at', 'ទទួលនៅ')}: ${string(monster, 'destinationId', t('Starter companion', 'មិត្តរួមដំណើរដំបូង'))}',
          ),
          if (stage < 2)
            OutlinedButton(
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
              child: Text(
                '${t('Evolve', 'វិវត្ត')} • Lv $requiredLevel • ${75 * (stage + 1)} ${t('gold', 'មាស')}',
              ),
            ),
        ],
      ),
    );
  }
}
