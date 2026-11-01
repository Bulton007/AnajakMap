/// Stable game IDs stay unchanged so existing collections and rewards survive.
/// These are original fantasy designs, not depictions of named sacred beings.
enum CreatureDesign { snake, lion, bird, makara, turtle, monkey }

class CreatureConcept {
  const CreatureConcept(
    this.id,
    this.name,
    this.khmerName,
    this.design,
    this.color,
    this.accent,
    this.lore,
    this.khmerLore,
  );
  final String id, name, khmerName, lore, khmerLore;
  final CreatureDesign design;
  final int color, accent;
}

const creatureConcepts = <CreatureConcept>[
  CreatureConcept(
    'mossling',
    'Lotus Naga',
    'នាគឈូក',
    CreatureDesign.snake,
    0xff3caa82,
    0xfff4d78d,
    'An original emerald serpent with a lotus crest, watching over imaginary garden trails.',
    'ពស់វេទមន្តពណ៌មរកត មានផ្កាឈូកលើក្បាល ថែរក្សាផ្លូវសួនក្នុងពិភពស្រមៃ។',
  ),
  CreatureConcept(
    'amberhorn',
    'Dawn Singha',
    'សិង្ហអរុណ',
    CreatureDesign.lion,
    0xffdda653,
    0xfff9df9e,
    'A friendly guardian cub with a spiral mane and tiny sunrise jewels.',
    'កូនសិង្ហយាមដ៏រួសរាយ មានរោមកវង់ និងត្បូងតូចពណ៌អរុណ។',
  ),
  CreatureConcept(
    'moonwarden',
    'Moon Krut',
    'គ្រុឌចន្ទ្រា',
    CreatureDesign.bird,
    0xff8b78bf,
    0xfff4d88d,
    'An original winged companion with layered feathers and a moonlit crest.',
    'ដៃគូមានស្លាបវេទមន្ត រោមជាស្រទាប់ និងក្បាលភ្លឺដូចព្រះចន្ទ។',
  ),
  CreatureConcept(
    'bubblefin',
    'River Makara',
    'មករទន្លេ',
    CreatureDesign.makara,
    0xff41aebe,
    0xfff2d591,
    'A playful water chimera with a curling snout and a flowing wave tail.',
    'សត្វទឹកវេទមន្តចូលចិត្តលេង មានច្រមុះកោង និងកន្ទុយដូចរលក។',
  ),
  CreatureConcept(
    'coralclaw',
    'Coral Terrapin',
    'អណ្ដើកផ្កាថ្ម',
    CreatureDesign.turtle,
    0xffd97d8f,
    0xfff8daa0,
    'A little reef guardian with a patterned coral shell and golden flippers.',
    'អ្នកថែរក្សាថ្មប៉ប្រះទឹកតូច មានស្នូកលំនាំផ្កាថ្ម និងជើងពណ៌មាស។',
  ),
  CreatureConcept(
    'tidewing',
    'Cloud Vanara',
    'ពានរពពក',
    CreatureDesign.monkey,
    0xff78a9d7,
    0xfff7d68b,
    'An agile cloud monkey with a curling tail, gilded cuffs and a curious smile.',
    'ពានរពពករហ័សរហួន មានកន្ទុយកោង ខ្សែដៃពណ៌មាស និងស្នាមញញឹមចង់ដឹង។',
  ),
];

CreatureConcept? creatureConcept(String id) {
  for (final concept in creatureConcepts) {
    if (concept.id == id) return concept;
  }
  return null;
}

String creatureDisplayName(String id, {String language = 'en'}) {
  final concept = creatureConcept(id);
  return concept == null
      ? id
      : language == 'km'
      ? concept.khmerName
      : concept.name;
}

String creatureLore(String id, {String language = 'en'}) {
  final concept = creatureConcept(id);
  return concept == null
      ? ''
      : language == 'km'
      ? concept.khmerLore
      : concept.lore;
}

String creatureInspirationNotice({String language = 'en'}) => language == 'km'
    ? 'ដៃគូវេទមន្តដើម បំផុសគំនិតពីសិល្បៈ និងរឿងនិទានខ្មែរ។ ឈ្មោះ អំណាច និងរឿងរបស់ពួកវាត្រូវបានបង្កើតសម្រាប់ហ្គេមនេះ។'
    : 'Original fantasy companions inspired by Khmer art and storytelling. Their names, powers and stories are invented for this game.';
