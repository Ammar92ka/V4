import 'budget.dart';
import 'difficulty.dart';
import 'round_plan.dart';
import 'systems.dart';

/// سطر في سجل القرارات.
class HistoryEntry {
  final int round;
  final String category;
  final String title;
  final String choice;
  final String result;

  const HistoryEntry({
    required this.round,
    required this.category,
    required this.title,
    required this.choice,
    this.result = '',
  });

  Map<String, dynamic> toJson() => {
    'round': round,
    'category': category,
    'title': title,
    'choice': choice,
    'result': result,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    String s(String k) => json[k] is String ? json[k] as String : '';
    final r = json['round'];
    return HistoryEntry(
      round: r is num ? r.toInt() : 0,
      category: s('category'),
      title: s('title'),
      choice: s('choice'),
      result: s('result'),
    );
  }
}

/// أثر مؤجل ينتظر موعده (بعد عدد من أنصاف السنوات).
class PendingEffect {
  final int dueRound;
  final Effects effects;
  final List<LineChange> lines;
  final String source;

  const PendingEffect({
    required this.dueRound,
    this.effects = const Effects(),
    this.lines = const [],
    this.source = '',
  });

  Map<String, dynamic> toJson() => {
    'due': dueRound,
    'effects': effects.toJson(),
    'lines': [for (final l in lines) l.toJson()],
    'source': source,
  };

  factory PendingEffect.fromJson(Map<String, dynamic> json) {
    final lines = <LineChange>[];
    final raw = json['lines'];
    if (raw is List) {
      for (final l in raw) {
        final lc = LineChange.fromJson(l);
        if (lc.line.isNotEmpty) lines.add(lc);
      }
    }
    final due = json['due'];
    return PendingEffect(
      dueRound: due is num ? due.toInt() : 0,
      effects: Effects.fromJson(json['effects']),
      lines: lines,
      source: json['source'] is String ? json['source'] as String : '',
    );
  }
}

/// حالة الحملة كاملة. تحفظ وتستعاد بما فيها الجولة الحالية التي كتبها الذكاء الاصطناعي،
/// فلا تضيع عند إغلاق التطبيق ولا تُولَّد من جديد.
class GameState {
  /// نسخة صيغة الحفظ الحالية. نقبل أيضا النسخة 2 (قبل الأنظمة العميقة) ونرقيها تلقائيا.
  static const int schema = 4;
  static const Set<int> readableSchemas = {2, 3, 4};

  /// بذرة الأحداث العشوائية: ثابتة في الحفظ فتتكرر الحملة نفسها عند إعادة التشغيل.
  static const int defaultSeed = 1800;

  double treasury; // قروش
  double debt; // قروش
  int legitimacy;
  int army;
  int foreign;
  int education;
  Budget budget;

  /// أبعاد الاستقرار الستة؛ الرقم الكلي [stability] متوسطها.
  StabilityState stab;

  /// قوى الدولة (الانكشارية والعلماء...).
  Map<String, PowerState> powers;
  List<PowerProject> projects;

  /// اقتصاد الولايات والحبوب والتضخم والفساد.
  EconomyState econ;

  /// الدول: العلاقات والسفارات وشبكات التجسس.
  Map<String, CountryState> countries;

  /// شبكة التجسس الداخلي: 0 لا شيء، 1 محدودة، 2 واسعة.
  int domesticSpy;
  List<SpyReport> intel;
  DemographyState demog;
  WorldMemory world;

  /// عدد إجراءات الديوان المتاحة في نصف السنة الحالي.
  int courtActions;

  /// مبلغ يريد اللاعب تسديده من الدين في نهاية نصف السنة (إن توفر في الخزينة).
  double repay;

  /// ما فعله اللاعب في الديوان هذا النصف (يدخل التقرير ثم يفرغ).
  List<String> courtLog;

  /// أحداث نصف السنة الأخير (مناخ ومؤامرات وعلاقات وتجسس).
  List<String> events;

  int seed;

  /// مستوى الصعوبة: 0 سهل، 1 عادي، 2 صعب.
  int difficulty;

  /// الحروب الجارية.
  List<War> wars;

  /// الجزء الأجنبي من [debt] (الباقي دين داخلي). صفر قبل القروض الأجنبية.
  double foreignDebt;

  /// رقم نصف السنة الذي أعلنت فيه الدولة العجز عن السداد (-1 = لم يحدث).
  int defaultRound;

  /// أنصاف السنة المتتالية التي اضطرت فيها الدولة للاقتراض الطارئ.
  int emergencyStreak;

  /// هل إدارة الديون العامة تحصّل جزءا من الإيراد للدائنين الأجانب؟
  bool dadActive;

  /// المشروع القومي الجاري (واحد فقط) والمشاريع المنجزة.
  ActiveProject? project;
  List<String> completed;

  /// لقطات نصف سنوية للرسوم البيانية.
  List<StatPoint> series;

  /// رقم نصف السنة (0 = النصف الأول من 1800).
  int round;
  List<PendingEffect> pending;
  List<HistoryEntry> history;

  /// ملاحظة قصيرة يكتبها الذكاء الاصطناعي ليتذكر ما لا يتسع في الذاكرة المنظمة.
  String chronicle;

  /// نص تقرير نصف السنة الأخير، يرسل للذكاء الاصطناعي لتكتب الجولة التالية بناء عليه.
  String lastReport;

  /// الجولة الحالية واختيارات اللاعب فيها (null = لم يختر بعد).
  RoundPlan? plan;
  List<int?> picks;

  GameState({
    this.treasury = 3000000,
    this.debt = 6000000,
    this.legitimacy = 65,
    int stability = 55,
    StabilityState? stab,
    this.army = 45,
    this.foreign = 45,
    this.education = 15,
    Budget? budget,
    Map<String, PowerState>? powers,
    List<PowerProject>? projects,
    EconomyState? econ,
    Map<String, CountryState>? countries,
    this.domesticSpy = 0,
    List<SpyReport>? intel,
    DemographyState? demog,
    WorldMemory? world,
    this.courtActions = 2,
    this.repay = 0,
    List<String>? courtLog,
    List<String>? events,
    this.seed = defaultSeed,
    this.difficulty = 1,
    List<War>? wars,
    this.foreignDebt = 0,
    this.defaultRound = -1,
    this.emergencyStreak = 0,
    this.dadActive = false,
    this.project,
    List<String>? completed,
    List<StatPoint>? series,
    this.round = 0,
    List<PendingEffect>? pending,
    List<HistoryEntry>? history,
    this.chronicle = '',
    this.lastReport = '',
    this.plan,
    List<int?>? picks,
  }) : stab = stab ?? StabilityState.fromTotal(stability),
       budget = budget ?? Budget.initial1800(),
       powers = powers ?? defaultPowers(),
       projects = projects ?? <PowerProject>[],
       econ = econ ?? EconomyState(),
       countries = countries ?? defaultCountries(),
       intel = intel ?? <SpyReport>[],
       demog = demog ?? DemographyState(),
       world = world ?? WorldMemory(),
       courtLog = courtLog ?? <String>[],
       events = events ?? <String>[],
       wars = wars ?? <War>[],
       completed = completed ?? <String>[],
       series = series ?? <StatPoint>[],
       pending = pending ?? <PendingEffect>[],
       history = history ?? <HistoryEntry>[],
       picks = picks ?? <int?>[null, null, null];

  Difficulty get diff => Difficulty(difficulty);

  /// الاستقرار الكلي: متوسط الأبعاد الستة.
  int get stability => stab.rounded;

  /// يضبط الاستقرار الكلي بإزاحة كل الأبعاد بالتساوي (للاختبارات والاستعادة).
  set stability(int value) => stab.shiftAll(value.clamp(0, 100) - stab.total);

  bool get hasAllPicks => picks.length == 3 && picks.every((p) => p != null);

  Map<String, dynamic> toJson() => {
    'schema': schema,
    'treasury': treasury,
    'debt': debt,
    'legitimacy': legitimacy,
    'stability': stability,
    'stab': stab.toJson(),
    'army': army,
    'foreign': foreign,
    'education': education,
    'budget': budget.toJson(),
    'powers': [for (final p in powers.values) p.toJson()],
    'projects': [for (final p in projects) p.toJson()],
    'econ': econ.toJson(),
    'countries': [for (final c in countries.values) c.toJson()],
    'domesticSpy': domesticSpy,
    'intel': [for (final r in intel) r.toJson()],
    'demog': demog.toJson(),
    'world': world.toJson(),
    'courtActions': courtActions,
    'repay': repay,
    'courtLog': courtLog,
    'events': events,
    'seed': seed,
    'difficulty': difficulty,
    'wars': [for (final w in wars) w.toJson()],
    'foreignDebt': foreignDebt,
    'defaultRound': defaultRound,
    'emergencyStreak': emergencyStreak,
    'dadActive': dadActive,
    'project': project?.toJson(),
    'completed': completed,
    'series': [for (final p in series) p.toList()],
    'round': round,
    'pending': [for (final p in pending) p.toJson()],
    'history': [for (final h in history) h.toJson()],
    'chronicle': chronicle,
    'lastReport': lastReport,
    'plan': plan?.toJson(),
    'picks': picks,
  };

  /// يرمي خطأ إذا كان الحفظ بصيغة غير مدعومة؛ والخدمة التي تستدعيه تلتقط الخطأ.
  factory GameState.fromJson(Map<String, dynamic> json) {
    final sc = json['schema'];
    if (sc is! num || !readableSchemas.contains(sc.toInt())) {
      throw const FormatException('صيغة حفظ غير مدعومة');
    }
    double money(String k, double d) {
      final v = json[k];
      return v is num && v.isFinite ? v.toDouble().clamp(0.0, 1e15).toDouble() : d;
    }

    int ind(String k, int d) {
      final v = json[k];
      return v is num && v.isFinite ? v.round().clamp(0, 100).toInt() : d;
    }

    List<String> strings(Object? raw, int max) {
      if (raw is! List) return <String>[];
      return [
        for (final x in raw)
          if (x is String && x.trim().isNotEmpty) x.trim(),
      ].take(max).toList();
    }

    final history = <HistoryEntry>[];
    final rawHistory = json['history'];
    if (rawHistory is List) {
      for (final h in rawHistory) {
        if (h is Map) history.add(HistoryEntry.fromJson(Map<String, dynamic>.from(h)));
      }
    }
    final pending = <PendingEffect>[];
    final rawPending = json['pending'];
    if (rawPending is List) {
      for (final p in rawPending) {
        if (p is Map) pending.add(PendingEffect.fromJson(Map<String, dynamic>.from(p)));
      }
    }
    RoundPlan? plan;
    final rawPlan = json['plan'];
    if (rawPlan is Map) {
      final parsed = RoundPlan.fromJson(Map<String, dynamic>.from(rawPlan));
      if (parsed.decisions.length == 3) plan = parsed;
    }
    final picks = <int?>[null, null, null];
    final rawPicks = json['picks'];
    if (plan != null && rawPicks is List) {
      for (var i = 0; i < 3 && i < rawPicks.length; i++) {
        final p = rawPicks[i];
        if (p is num) {
          final idx = p.toInt();
          if (idx >= 0 && idx < plan.decisions[i].options.length) picks[i] = idx;
        }
      }
    }
    final projects = <PowerProject>[];
    final rawProjects = json['projects'];
    if (rawProjects is List) {
      for (final p in rawProjects) {
        final pr = PowerProject.fromJson(p);
        if (pr != null) projects.add(pr);
      }
    }
    final intel = <SpyReport>[];
    final rawIntel = json['intel'];
    if (rawIntel is List) {
      for (final r in rawIntel) {
        final rep = SpyReport.fromJson(r);
        if (rep != null) intel.add(rep);
      }
    }
    final wars = <War>[];
    final rawWars = json['wars'];
    if (rawWars is List) {
      for (final w in rawWars) {
        final war = War.fromJson(w);
        if (war != null && !wars.any((x) => x.enemy == war.enemy)) wars.add(war);
      }
    }
    final series = <StatPoint>[];
    final rawSeries = json['series'];
    if (rawSeries is List) {
      for (final p in rawSeries) {
        final pt = StatPoint.fromList(p);
        if (pt != null) series.add(pt);
      }
    }
    final debtNow = money('debt', 6000000);
    final foreignRaw = money('foreignDebt', 0);
    final money0 = foreignRaw > debtNow ? debtNow : foreignRaw;
    final round = json['round'];
    final difficultyRaw = json['difficulty'];
    final defaultRaw = json['defaultRound'];
    final streakRaw = json['emergencyStreak'];
    final stabilityTotal = ind('stability', 55);
    final seedRaw = json['seed'];
    final actions = json['courtActions'];
    final spy = json['domesticSpy'];
    return GameState(
      treasury: money('treasury', 3000000),
      debt: money('debt', 6000000),
      legitimacy: ind('legitimacy', 65),
      stability: stabilityTotal,
      stab: StabilityState.fromJson(json['stab'], stabilityTotal),
      army: ind('army', 45),
      foreign: ind('foreign', 45),
      education: ind('education', 15),
      budget: Budget.fromJson(json['budget']),
      powers: powersFromJson(json['powers']),
      projects: projects,
      econ: EconomyState.fromJson(json['econ']),
      countries: countriesFromJson(json['countries']),
      domesticSpy: spy is num ? spy.toInt().clamp(0, 2).toInt() : 0,
      intel: intel.length > 8 ? intel.sublist(intel.length - 8) : intel,
      demog: DemographyState.fromJson(json['demog']),
      world: WorldMemory.fromJson(json['world']),
      courtActions: actions is num ? actions.toInt().clamp(0, 9).toInt() : 2,
      repay: money('repay', 0),
      courtLog: strings(json['courtLog'], 12),
      events: strings(json['events'], 16),
      seed: seedRaw is num ? seedRaw.toInt() : defaultSeed,
      difficulty: difficultyRaw is num ? difficultyRaw.toInt().clamp(0, 2).toInt() : 1,
      wars: wars.length > 3 ? wars.sublist(0, 3) : wars,
      foreignDebt: money0,
      defaultRound: defaultRaw is num ? defaultRaw.toInt() : -1,
      emergencyStreak: streakRaw is num ? streakRaw.toInt().clamp(0, 1000).toInt() : 0,
      dadActive: json['dadActive'] == true,
      project: ActiveProject.fromJson(json['project']),
      completed: strings(json['completed'], 40),
      series: series.length > 460 ? series.sublist(series.length - 460) : series,
      round: round is num ? round.toInt().clamp(0, 100000).toInt() : 0,
      pending: pending,
      history: history,
      chronicle: json['chronicle'] is String ? json['chronicle'] as String : '',
      lastReport: json['lastReport'] is String ? json['lastReport'] as String : '',
      plan: plan,
      picks: picks,
    );
  }

  /// نسخة مستقلة (للتجارب والاختبارات).
  GameState copy() => GameState.fromJson(toJson());
}
