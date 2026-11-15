/// نماذج الأنظمة العميقة: الاستقرار، قوى الدولة، الاقتصاد، الدول والسفارات
/// والجواسيس، السكان، وذاكرة العالم. كلها تحفظ وتستعاد مع الحملة.
library;

double clampD(num v, double lo, double hi) {
  final d = v.toDouble();
  if (!d.isFinite) return lo;
  return d < lo ? lo : (d > hi ? hi : d);
}

double _num(Object? v, double d) => v is num && v.isFinite ? v.toDouble() : d;
int _int(Object? v, int d) => v is num && v.isFinite ? v.round() : d;
String _str(Object? v) => v is String ? v : '';
bool _bool(Object? v, bool d) => v is bool ? v : d;

// ───────────────────────── الاستقرار ─────────────────────────

/// الاستقرار الكلي هو متوسط ستة أبعاد، وكل بعد يتحرك بأسبابه.
class StabilityState {
  static const List<String> keys = [
    'economic',
    'social',
    'military',
    'political',
    'religious',
    'regional',
  ];

  static const Map<String, String> labels = {
    'economic': 'اقتصادي',
    'social': 'اجتماعي',
    'military': 'عسكري',
    'political': 'سياسي',
    'religious': 'ديني',
    'regional': 'إقليمي',
  };

  /// فروق البدء عن المتوسط (مجموعها صفر).
  static const Map<String, double> offsets = {
    'economic': -5,
    'social': 0,
    'military': 0,
    'political': 5,
    'religious': 10,
    'regional': -10,
  };

  final Map<String, double> _v;
  StabilityState._(this._v);

  /// يبني الأبعاد من رقم كلي. الفروق تضيق قرب الحدين فيبقى المتوسط مطابقا للرقم.
  factory StabilityState.fromTotal(int total) {
    final t = total.clamp(0, 100).toInt();
    final scale = (((t < 100 - t ? t : 100 - t)) / 10).clamp(0.0, 1.0).toDouble();
    return StabilityState._({
      for (final k in keys) k: clampD(t + offsets[k]! * scale, 0, 100),
    });
  }

  factory StabilityState.fromJson(Object? json, int fallbackTotal) {
    if (json is! Map) return StabilityState.fromTotal(fallbackTotal);
    return StabilityState._({
      for (final k in keys) k: clampD(_num(json[k], fallbackTotal.toDouble()), 0, 100),
    });
  }

  double operator [](String k) => _v[k] ?? 55;

  void shift(String k, double d) {
    if (_v.containsKey(k)) _v[k] = clampD(_v[k]! + d, 0, 100);
  }

  void shiftAll(double d) {
    for (final k in keys) {
      _v[k] = clampD(_v[k]! + d, 0, 100);
    }
  }

  double get total => keys.fold(0.0, (a, k) => a + _v[k]!) / keys.length;
  int get rounded => total.round();

  /// عدد الأبعاد التي هبطت إلى [threshold] أو أقل.
  int countBelow(double threshold) => keys.where((k) => _v[k]! <= threshold).length;

  /// أضعف بعد (للتنبيه في الواجهة).
  String get weakest {
    var best = keys.first;
    for (final k in keys) {
      if (_v[k]! < _v[best]!) best = k;
    }
    return best;
  }

  Map<String, double> toJson() => {for (final k in keys) k: _v[k]!};

  StabilityState copy() => StabilityState._({..._v});
}

// ───────────────────────── قوى الدولة ─────────────────────────

class PowerDef {
  final String key;
  final String name;
  final String about;

  /// معامل الميل للعنف: يضخم الخطر عند الغضب.
  final double militancy;
  final double influence;
  final double satisfaction;

  const PowerDef(
    this.key,
    this.name,
    this.about,
    this.militancy,
    this.influence,
    this.satisfaction,
  );
}

const List<PowerDef> powerDefs = [
  PowerDef('janissaries', 'الانكشارية', 'جند العاصمة وتجارها؛ يخلعون السلاطين إذا غضبوا', 1.1, 90, 35),
  PowerDef('ulema', 'العلماء', 'القضاء والتعليم والفتوى وأوقاف ضخمة', 0.65, 80, 60),
  PowerDef('governors', 'الأعيان والولاة', 'أعيان الأناضول والروملي وولاة الأطراف', 0.8, 70, 50),
  PowerDef('tax_farmers', 'الملتزمون والصرافون', 'ملتزمو الضرائب والمقرضون في العاصمة', 0.75, 65, 45),
  PowerDef('tribes', 'العشائر', 'عشائر البادية وأطراف الشام والعراق والحجاز', 0.7, 50, 55),
  PowerDef('mamluks', 'المماليك وأمراء الأطراف', 'أمراء مصر وبقايا النفوذ المملوكي', 1.0, 75, 30),
  PowerDef('merchants', 'التجار', 'تجار الموانئ والمحميون الأجانب', 0.45, 60, 65),
  PowerDef('minorities', 'الملل والأقليات', 'الروم والأرمن واليهود والسلاف المسيحيون', 0.55, 45, 50),
];

PowerDef? powerDef(String key) {
  for (final d in powerDefs) {
    if (d.key == key) return d;
  }
  return null;
}

bool isPowerKey(String key) => powerDef(key) != null;

class PowerState {
  final String key;
  double influence;
  double satisfaction;
  bool dissolved;

  PowerState(this.key, this.influence, this.satisfaction, {this.dissolved = false});

  PowerDef get def => powerDef(key)!;
  String get name => def.name;

  /// الخطر مشتق: النفوذ مضروبا في الغضب ومعامل الميل للعنف.
  double get danger {
    if (dissolved) return 0;
    return clampD(
      influence * (0.4 + 0.6 * (100 - satisfaction) / 100) * def.militancy,
      0,
      100,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'influence': influence,
    'satisfaction': satisfaction,
    'dissolved': dissolved,
  };

  PowerState copy() => PowerState(key, influence, satisfaction, dissolved: dissolved);
}

Map<String, PowerState> defaultPowers() => {
  for (final d in powerDefs) d.key: PowerState(d.key, d.influence, d.satisfaction),
};

Map<String, PowerState> powersFromJson(Object? json) {
  final out = defaultPowers();
  if (json is List) {
    for (final p in json) {
      if (p is! Map) continue;
      final key = _str(p['key']);
      final cur = out[key];
      if (cur == null) continue;
      cur.influence = clampD(_num(p['influence'], cur.influence), 0, 100);
      cur.satisfaction = clampD(_num(p['satisfaction'], cur.satisfaction), 0, 100);
      cur.dissolved = _bool(p['dissolved'], false);
    }
  }
  return out;
}

/// مشروع طويل على قوة: إصلاح أو احتواء أو دمج، يعمل كل نصف سنة حتى ينتهي.
class PowerProject {
  final String power;
  final String kind; // reform | contain | merge
  int remaining;

  PowerProject(this.power, this.kind, this.remaining);

  static const Map<String, String> kindLabels = {
    'reform': 'إصلاح',
    'contain': 'احتواء',
    'merge': 'دمج',
  };

  Map<String, dynamic> toJson() => {'power': power, 'kind': kind, 'remaining': remaining};

  static PowerProject? fromJson(Object? json) {
    if (json is! Map) return null;
    final p = _str(json['power']);
    final k = _str(json['kind']);
    if (!isPowerKey(p) || !kindLabels.containsKey(k)) return null;
    final r = _int(json['remaining'], 0);
    if (r <= 0) return null;
    return PowerProject(p, k, r.clamp(1, 20).toInt());
  }
}

// ───────────────────────── الاقتصاد العميق ─────────────────────────

class ProvinceDef {
  final String key;
  final String name;
  final double weight;
  final double mood;

  /// ميل الولاية إلى الانفصال (معدل الارتفاع الأساسي لنصف السنة).
  final double sep;

  /// الاستقلال الذاتي الابتدائي (0 ولاء كامل، 100 استقلال فعلي).
  final double autonomy;
  const ProvinceDef(this.key, this.name, this.weight, this.mood, this.sep, this.autonomy);
}

/// أوزان الولايات في قاعدة الجباية (مجموعها 1).
const List<ProvinceDef> provinceDefs = [
  ProvinceDef('rumelia', 'الروملي والبلقان', 0.26, 45, 0.7, 20),
  ProvinceDef('anatolia', 'الأناضول', 0.34, 65, 0.05, 3),
  ProvinceDef('egypt', 'مصر', 0.20, 40, 0.9, 35),
  ProvinceDef('syria', 'الشام', 0.10, 60, 0.35, 12),
  ProvinceDef('iraq', 'العراق', 0.07, 55, 0.35, 15),
  ProvinceDef('hijaz', 'الحجاز واليمن', 0.03, 50, 0.45, 20),
];

class ProvinceState {
  static const String loyal = 'loyal';
  static const String autonomousStatus = 'autonomous';
  static const String independent = 'independent';

  final String key;
  double mood;

  /// محصول هذا النصف: 1 عادي، أقل من 1 جفاف، أكثر من 1 وفرة.
  double harvest;

  /// الاستقلال الذاتي: كلما ارتفع اقتربت الولاية من الانفصال.
  double autonomy;

  /// loyal | autonomous (شبه مستقلة تدفع جزءا من إيرادها) | independent (مفقودة).
  String status;

  ProvinceState(this.key, this.mood, {this.harvest = 1.0, double? autonomy, this.status = loyal})
    : autonomy = autonomy ?? provinceDefs.firstWhere((d) => d.key == key).autonomy;

  ProvinceDef get def => provinceDefs.firstWhere((d) => d.key == key);
  String get name => def.name;

  bool get isLost => status == independent;

  /// وزنها الفعلي في الإيراد: كاملة للموالية، 40% للمستقلة ذاتيا، صفر للمفقودة.
  double get effWeight =>
      status == loyal ? def.weight : (status == autonomousStatus ? def.weight * 0.4 : 0.0);

  static const Map<String, String> statusLabels = {
    loyal: 'موالية',
    autonomousStatus: 'شبه مستقلة',
    independent: 'مفقودة',
  };

  Map<String, dynamic> toJson() => {
    'key': key,
    'mood': mood,
    'harvest': harvest,
    'autonomy': autonomy,
    'status': status,
  };
}

class EconomyState {
  /// مرجع المزاج: الوسط المرجح الابتدائي، فيكون المضاعف 1.0 في بداية الحملة.
  static final double moodRef = provinceDefs.fold(0.0, (a, d) => a + d.weight * d.mood);

  static const double corruptionRef = 45;

  /// حصة الأرض في إيراد الولاية (تتأثر بالمحصول).
  static const double landShare = 0.5;

  final Map<String, ProvinceState> provinces;

  /// مؤشر سعر الحبوب (100 عادي).
  double grain;

  /// التضخم السنوي بالمئة.
  double inflation;

  /// الفساد 0..100: يأكل من الجباية.
  double corruption;
  int deficitStreak;
  int surplusStreak;

  /// مؤشر الأسعار التراكمي منذ 1800.
  double priceIndex;

  EconomyState({
    Map<String, ProvinceState>? provinces,
    this.grain = 100,
    this.inflation = 2.0,
    this.corruption = 45,
    this.deficitStreak = 0,
    this.surplusStreak = 0,
    this.priceIndex = 1.0,
  }) : provinces = provinces ?? {for (final d in provinceDefs) d.key: ProvinceState(d.key, d.mood)};

  /// مجموع أوزان الولايات الفعالة (1.0 عند البدء، ينقص بالانفصال).
  double get activeWeight => provinces.values.fold(0.0, (a, p) => a + p.effWeight);

  /// متوسط مزاج الولايات الفعالة بأوزانها.
  double get avgMood {
    final w = activeWeight;
    if (w <= 0) return 0;
    return provinces.values.fold(0.0, (a, p) => a + p.effWeight * p.mood) / w;
  }

  /// مضاعف الإيراد من المزاج والمحصول والفساد. يساوي 1.0 تماما في بداية الحملة.
  double get revenueMultiplier {
    var base = 0.0;
    for (final p in provinces.values) {
      final moodF = 1 + 0.002 * (p.mood - moodRef);
      final harvestF = 1 - landShare * (1 - p.harvest);
      base += p.effWeight * moodF * harvestF;
    }
    final corr = clampD(1 - 0.003 * (corruption - corruptionRef), 0.85, 1.10);
    final m = base * corr;
    return (m - 1).abs() < 1e-9 ? 1.0 : m;
  }

  /// النمو الاسمي لكل نصف سنة (2% سنويا = 1% لنصف السنة).
  double get nominalGrowth => clampD(inflation, 0, 40) / 200;

  Map<String, dynamic> toJson() => {
    'provinces': [for (final p in provinces.values) p.toJson()],
    'grain': grain,
    'inflation': inflation,
    'corruption': corruption,
    'deficitStreak': deficitStreak,
    'surplusStreak': surplusStreak,
    'priceIndex': priceIndex,
  };

  factory EconomyState.fromJson(Object? json) {
    final e = EconomyState();
    if (json is! Map) return e;
    final raw = json['provinces'];
    if (raw is List) {
      for (final p in raw) {
        if (p is! Map) continue;
        final cur = e.provinces[_str(p['key'])];
        if (cur == null) continue;
        cur.mood = clampD(_num(p['mood'], cur.mood), 0, 100);
        cur.harvest = clampD(_num(p['harvest'], 1.0), 0.2, 1.5);
        cur.autonomy = clampD(_num(p['autonomy'], cur.autonomy), 0, 100);
        final st = _str(p['status']);
        if (ProvinceState.statusLabels.containsKey(st)) cur.status = st;
      }
    }
    e.grain = clampD(_num(json['grain'], 100), 40, 400);
    e.inflation = clampD(_num(json['inflation'], 2), 0, 40);
    e.corruption = clampD(_num(json['corruption'], 45), 0, 100);
    e.deficitStreak = _int(json['deficitStreak'], 0).clamp(0, 1000).toInt();
    e.surplusStreak = _int(json['surplusStreak'], 0).clamp(0, 1000).toInt();
    e.priceIndex = clampD(_num(json['priceIndex'], 1.0), 0.1, 1000);
    return e;
  }
}

// ───────────────────────── الدول والسفارات والجواسيس ─────────────────────────

class CountryDef {
  final String key;
  final String name;
  final double relation;
  final bool embassy;

  /// الاقتصاد والقوة العسكرية الابتدائيان بمقياس واحد مع الدولة العثمانية
  /// (اقتصادنا 100 والجيش بمؤشرنا من 100). تقديرات للعب لا إحصاءات تاريخية دقيقة.
  final double economy;
  final double military;

  /// نمو سنوي أساسي للاقتصاد والجيش (كسر).
  final double ecoGrowth;
  final double milGrowth;

  const CountryDef(
    this.key,
    this.name,
    this.relation,
    this.embassy,
    this.economy,
    this.military,
    this.ecoGrowth,
    this.milGrowth,
  );
}

const List<CountryDef> countryDefs = [
  CountryDef('britain', 'بريطانيا', 62, true, 220, 85, 0.024, 0.016),
  CountryDef('austria', 'النمسا', 52, true, 110, 80, 0.011, 0.007),
  CountryDef('france', 'فرنسا', 30, false, 170, 120, 0.016, 0.010),
  CountryDef('russia', 'روسيا', 50, false, 140, 110, 0.015, 0.012),
  CountryDef('persia', 'إيران', 45, false, 45, 30, 0.004, 0.003),
  CountryDef('germany', 'بروسيا وألمانيا', 45, false, 70, 55, 0.024, 0.016),
];

CountryDef? countryDef(String key) {
  for (final d in countryDefs) {
    if (d.key == key) return d;
  }
  return null;
}

bool isCountryKey(String key) => countryDef(key) != null;

class CountryState {
  final String key;
  double relation;
  bool embassy;

  /// شبكة التجسس على هذه الدولة: 0 لا شيء، 1 محدودة، 2 واسعة.
  int spy;

  /// آخر جولة وقعت فيها معاهدة تجارية (للمهلة بين المعاهدات).
  int lastTreaty;

  /// اقتصاد الدولة وقوتها العسكرية بمقياس واحد مع الدولة العثمانية (انظر CountryDef).
  double economy;
  double military;

  CountryState(
    this.key,
    this.relation, {
    this.embassy = false,
    this.spy = 0,
    this.lastTreaty = -999,
    double? economy,
    double? military,
  }) : economy = economy ?? countryDef(key)!.economy,
       military = military ?? countryDef(key)!.military;

  String get name => countryDef(key)!.name;

  /// جودة المعلومات: سفارة + شبكة تجسس.
  int get intelQuality => spy + (embassy ? 1 : 0);

  Map<String, dynamic> toJson() => {
    'key': key,
    'relation': relation,
    'embassy': embassy,
    'spy': spy,
    'lastTreaty': lastTreaty,
    'economy': economy,
    'military': military,
  };
}

Map<String, CountryState> defaultCountries() => {
  for (final d in countryDefs) d.key: CountryState(d.key, d.relation, embassy: d.embassy),
};

Map<String, CountryState> countriesFromJson(Object? json) {
  final out = defaultCountries();
  if (json is List) {
    for (final c in json) {
      if (c is! Map) continue;
      final cur = out[_str(c['key'])];
      if (cur == null) continue;
      cur.relation = clampD(_num(c['relation'], cur.relation), 0, 100);
      cur.embassy = _bool(c['embassy'], cur.embassy);
      cur.spy = _int(c['spy'], 0).clamp(0, 2).toInt();
      cur.lastTreaty = _int(c['lastTreaty'], -999);
      cur.economy = clampD(_num(c['economy'], cur.economy), 5, 5000);
      cur.military = clampD(_num(c['military'], cur.military), 3, 400);
    }
  }
  return out;
}

/// تقرير استخبارات: ادعاء بدرجة موثوقية، وقد يكون كاذبا. الحقيقة محفوظة ولا تظهر
/// للاعب ولا للذكاء الاصطناعي إلا بعد نصف سنة (revealed).
class SpyReport {
  final int round;
  final String target; // مفتاح دولة أو 'domestic'
  final String claim;
  final int reliability; // نسبة مئوية معروضة
  final bool truth;
  bool revealed;

  SpyReport({
    required this.round,
    required this.target,
    required this.claim,
    required this.reliability,
    required this.truth,
    this.revealed = false,
  });

  Map<String, dynamic> toJson() => {
    'round': round,
    'target': target,
    'claim': claim,
    'reliability': reliability,
    'truth': truth,
    'revealed': revealed,
  };

  static SpyReport? fromJson(Object? json) {
    if (json is! Map) return null;
    final claim = _str(json['claim']);
    if (claim.isEmpty) return null;
    return SpyReport(
      round: _int(json['round'], 0),
      target: _str(json['target']),
      claim: claim,
      reliability: _int(json['reliability'], 50).clamp(0, 100).toInt(),
      truth: _bool(json['truth'], false),
      revealed: _bool(json['revealed'], false),
    );
  }
}

// ───────────────────────── السكان والتعليم ─────────────────────────

class DemographyState {
  /// بالملايين (تقديري للعبة).
  double population;

  /// نسبة القراءة والكتابة بالمئة (تقديرية).
  double literacy;

  /// عدد المدارس الابتدائية (تقديري).
  double schools;

  DemographyState({this.population = 26.0, this.literacy = 3.0, this.schools = 9000});

  Map<String, dynamic> toJson() => {
    'population': population,
    'literacy': literacy,
    'schools': schools,
  };

  factory DemographyState.fromJson(Object? json) {
    if (json is! Map) return DemographyState();
    return DemographyState(
      population: clampD(_num(json['population'], 26.0), 1, 500),
      literacy: clampD(_num(json['literacy'], 3.0), 0, 100),
      schools: clampD(_num(json['schools'], 9000), 0, 1e7),
    );
  }
}

// ───────────────────────── ذاكرة العالم ─────────────────────────

/// ذاكرة منظمة يحدثها الذكاء الاصطناعي كل جولة: قوائم قصيرة بدل نص طويل،
/// فتوفر التوكنات وتقل فرصة أن ينسى حربا أو معاهدة.
class WorldMemory {
  static const int maxItems = 6;
  static const int maxLen = 90;

  final List<String> wars;
  final List<String> alliances;
  final List<String> reforms;
  final List<String> promises;

  WorldMemory({
    List<String>? wars,
    List<String>? alliances,
    List<String>? reforms,
    List<String>? promises,
  }) : wars = _clean(wars),
       alliances = _clean(alliances),
       reforms = _clean(reforms),
       promises = _clean(promises);

  static List<String> _clean(Object? raw) {
    if (raw is! List) return <String>[];
    final out = <String>[];
    for (final x in raw) {
      if (x is! String) continue;
      var t = x.trim();
      if (t.isEmpty) continue;
      if (t.length > maxLen) t = '${t.substring(0, maxLen - 1).trimRight()}…';
      out.add(t);
      if (out.length >= maxItems) break;
    }
    return out;
  }

  bool get isEmpty =>
      wars.isEmpty && alliances.isEmpty && reforms.isEmpty && promises.isEmpty;

  Map<String, dynamic> toJson() => {
    'wars': wars,
    'alliances': alliances,
    'reforms': reforms,
    'promises': promises,
  };

  factory WorldMemory.fromJson(Object? json) {
    if (json is! Map) return WorldMemory();
    return WorldMemory(
      wars: _clean(json['wars']),
      alliances: _clean(json['alliances']),
      reforms: _clean(json['reforms']),
      promises: _clean(json['promises']),
    );
  }
}

// ───────────────────────── الحروب والمشاريع والرسوم ─────────────────────────

/// حرب جارية. تحسبها اللعبة بالأرقام؛ والذكاء الاصطناعي يكتب سردها فقط.
class War {
  final String enemy;
  final int startRound;

  /// هل أعلنا نحن الحرب (وإلا فقد أُعلنت علينا).
  final bool byUs;

  /// نقاط الحرب من -100 (هزيمة) إلى +100 (نصر).
  double score;

  /// عدد أنصاف السنة التي مرت عليها.
  int halves;

  War(this.enemy, this.startRound, {this.byUs = false, this.score = 0, this.halves = 0});

  String get enemyName => countryDef(enemy)?.name ?? enemy;

  Map<String, dynamic> toJson() => {
    'enemy': enemy,
    'startRound': startRound,
    'byUs': byUs,
    'score': score,
    'halves': halves,
  };

  static War? fromJson(Object? json) {
    if (json is! Map) return null;
    final e = _str(json['enemy']);
    if (!isCountryKey(e)) return null;
    return War(
      e,
      _int(json['startRound'], 0),
      byUs: _bool(json['byUs'], false),
      score: clampD(_num(json['score'], 0), -100, 100),
      halves: _int(json['halves'], 0).clamp(0, 1000).toInt(),
    );
  }
}

/// المشروع القومي الجاري. واحد فقط في كل وقت.
class ActiveProject {
  final String key;

  /// المدة الكلية بأنصاف السنة.
  final int halves;

  /// عدد الأقساط المدفوعة.
  int funded;

  /// القسط لنصف السنة (قروش).
  final double installment;
  final int startRound;

  /// أنصاف السنة المتتالية التي تعثر فيها التمويل.
  int stalled;

  ActiveProject(
    this.key,
    this.halves,
    this.installment,
    this.startRound, {
    this.funded = 0,
    this.stalled = 0,
  });

  /// نسبة الاكتمال من 0 إلى 1.
  double get progress => halves <= 0 ? 0 : (funded / halves).clamp(0.0, 1.0).toDouble();
  int get remaining => (halves - funded).clamp(0, halves).toInt();

  Map<String, dynamic> toJson() => {
    'key': key,
    'halves': halves,
    'installment': installment,
    'startRound': startRound,
    'funded': funded,
    'stalled': stalled,
  };

  static ActiveProject? fromJson(Object? json) {
    if (json is! Map) return null;
    final k = _str(json['key']);
    final h = _int(json['halves'], 0);
    if (k.isEmpty || h <= 0) return null;
    return ActiveProject(
      k,
      h.clamp(1, 60).toInt(),
      clampD(_num(json['installment'], 0), 0, 1e13),
      _int(json['startRound'], 0),
      funded: _int(json['funded'], 0).clamp(0, h).toInt(),
      stalled: _int(json['stalled'], 0).clamp(0, 1000).toInt(),
    );
  }
}

/// نقطة في الرسوم البيانية: لقطة من الحالة بعد نصف سنة.
class StatPoint {
  static const int fields = 12;

  final int round;
  final double treasury;
  final double debt;

  /// الإيراد السنوي الاسمي.
  final double revenue;
  final int legitimacy;
  final int stability;
  final int army;
  final int foreign;
  final int education;
  final double population;
  final double literacy;
  final double inflation;

  const StatPoint({
    required this.round,
    required this.treasury,
    required this.debt,
    required this.revenue,
    required this.legitimacy,
    required this.stability,
    required this.army,
    required this.foreign,
    required this.education,
    required this.population,
    required this.literacy,
    required this.inflation,
  });

  List<num> toList() => [
    round,
    treasury,
    debt,
    revenue,
    legitimacy,
    stability,
    army,
    foreign,
    education,
    population,
    literacy,
    inflation,
  ];

  static StatPoint? fromList(Object? raw) {
    if (raw is! List || raw.length < fields) return null;
    for (final v in raw.take(fields)) {
      if (v is! num || !v.isFinite) return null;
    }
    double d(int i) => (raw[i] as num).toDouble();
    int n(int i) => (raw[i] as num).round();
    return StatPoint(
      round: n(0),
      treasury: d(1),
      debt: d(2),
      revenue: d(3),
      legitimacy: n(4),
      stability: n(5),
      army: n(6),
      foreign: n(7),
      education: n(8),
      population: d(9),
      literacy: d(10),
      inflation: d(11),
    );
  }
}
