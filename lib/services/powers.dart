import 'dart:math';

import '../models/game_state.dart';
import '../models/systems.dart';
import 'sim_common.dart';
import 'stability.dart';

/// قوى الدولة: الرضا والنفوذ والخطر، والمشاريع الطويلة، والمؤامرات، وإجراءات الديوان.
class PowerRules {
  PowerRules._();

  static const double _armyShareRef = 8000000 / 18000000;

  /// مستوى الرضا الذي تميل إليه كل قوة بحسب ظروف الدولة الآن.
  /// عند الظروف الابتدائية يساوي الرضا الابتدائي بالضبط.
  static double signal(GameState s, String key, {required bool emergency}) {
    final rev = s.budget.totalRevenue;
    final armyShare = rev > 0 ? s.budget.lineValue('army') / rev : 0.0;
    final adminShare = rev > 0 ? s.budget.lineValue('admin') / rev : 0.0;
    final e = s.econ;
    switch (key) {
      case 'janissaries':
        return 35 + 150 * (armyShare - _armyShareRef) - (emergency ? 20 : 0);
      case 'ulema':
        return 60 + 0.5 * (s.legitimacy - 65) - 0.3 * (s.education - 15);
      case 'governors':
        return 50 + 0.5 * (e.avgMood - EconomyState.moodRef) - 100 * 0.3 * (adminShare - 0.25);
      case 'tax_farmers':
        return 45 + 0.5 * (e.corruption - EconomyState.corruptionRef);
      case 'tribes':
        return 55 - 0.25 * (e.grain - 100);
      case 'mamluks':
        return 30 + 0.3 * ((e.provinces['egypt']?.mood ?? 40) - 40);
      case 'merchants':
        return 65 + 0.3 * (s.foreign - 45) - 0.8 * (e.inflation - 2);
      case 'minorities':
        return 50 + 0.4 * (s.stability - 55);
    }
    return 50;
  }

  /// خطوة نصف السنة: ميل الرضا، المشاريع، والمؤامرات.
  static List<String> step(GameState s, {required bool emergency}) {
    final notes = <String>[];

    for (final p in s.powers.values) {
      if (p.dissolved) continue;
      final target = signal(s, p.key, emergency: emergency);
      p.satisfaction = clampD(p.satisfaction + 0.08 * (target - p.satisfaction), 0, 100);
    }

    final done = <PowerProject>[];
    for (final pr in s.projects) {
      final p = s.powers[pr.power];
      if (p == null || p.dissolved) {
        done.add(pr);
        continue;
      }
      switch (pr.kind) {
        case 'reform':
          p.influence = clampD(p.influence - 1.5, 0, 100);
          p.satisfaction = clampD(p.satisfaction + 1.5, 0, 100);
        case 'contain':
          p.influence = clampD(p.influence - 3, 0, 100);
          p.satisfaction = clampD(p.satisfaction - 1, 0, 100);
        case 'merge':
          p.influence = clampD(p.influence - 2.5, 0, 100);
          p.satisfaction = clampD(p.satisfaction + 1, 0, 100);
      }
      pr.remaining -= 1;
      if (pr.remaining <= 0) {
        done.add(pr);
        notes.add('اكتمل مشروع ${PowerProject.kindLabels[pr.kind]} ${p.name}');
      }
    }
    s.projects.removeWhere(done.contains);

    if (!inGrace(s)) notes.addAll(_plots(s));
    return notes;
  }

  static const Map<String, double> _detectChance = {'0': 0.0, '1': 0.45, '2': 0.80};

  static List<String> _plots(GameState s) {
    final notes = <String>[];
    final rng = rngFor(s, 11);
    for (final p in s.powers.values) {
      final danger = p.danger;
      if (danger < 60) continue;
      final chance = min(0.15, (danger - 60) / 300) * s.diff.events;
      if (rng.nextDouble() >= chance) continue;
      final detectP = _detectChance['${s.domesticSpy}'] ?? 0.0;
      if (rng.nextDouble() < detectP) {
        p.satisfaction = clampD(p.satisfaction - 4, 0, 100);
        s.legitimacy = (s.legitimacy + 1).clamp(0, 100).toInt();
        notes.add('كشفت الاستخبارات الداخلية مؤامرة لـ${p.name} وأُحبطت قبل أن تقع');
        s.intel.add(SpyReport(
          round: s.round,
          target: 'domestic',
          claim: 'أحبطنا مؤامرة لـ${p.name}',
          reliability: 100,
          truth: true,
          revealed: true,
        ));
      } else {
        notes.add(_explode(s, p));
      }
    }
    return notes;
  }

  /// مؤامرة لم تكشف: تنفجر بحسب طبيعة القوة.
  static String _explode(GameState s, PowerState p) {
    final st = s.stab;
    s.legitimacy = (s.legitimacy - 4).clamp(0, 100).toInt();
    switch (p.key) {
      case 'janissaries':
        st.shift('political', -5);
        st.shift('military', -4);
        s.army = (s.army - 3).clamp(0, 100).toInt();
        return 'تمرد الانكشارية في العاصمة وطالبوا برؤوس الوزراء';
      case 'ulema':
        st.shift('religious', -6);
        st.shift('political', -3);
        return 'أصدر العلماء بيانا يطعن في سياسات السلطان وهيجوا العامة';
      case 'governors':
        st.shift('regional', -6);
        st.shift('economic', -2);
        return 'تمرد أعيان وولاة في الأطراف وحبسوا الضرائب عن الخزينة';
      case 'tax_farmers':
        st.shift('economic', -5);
        st.shift('political', -2);
        return 'أوقف الملتزمون والصيارفة الإقراض وحبسوا الأموال عن الدولة';
      case 'tribes':
        st.shift('regional', -5);
        st.shift('military', -2);
        return 'اجتاحت العشائر الطرق والقرى الحدودية';
      case 'mamluks':
        st.shift('regional', -5);
        st.shift('political', -3);
        return 'تمرد المماليك وأمراء الأطراف في مصر وعطلوا جباية الولاية';
      case 'merchants':
        st.shift('economic', -4);
        st.shift('social', -2);
        return 'أضرب التجار وأغلقوا الأسواق احتجاجا على السياسات';
      default:
        st.shift('social', -5);
        st.shift('regional', -3);
        return 'اندلعت اضطرابات طائفية في الولايات المختلطة';
    }
  }

  // ───────────── إجراءات الديوان على القوى ─────────────

  static const double appeaseShare = 0.015;
  static const double reformShare = 0.020;
  static const double containShare = 0.010;
  static const double mergeShare = 0.012;
  static const double dissolveShare = 0.030;

  static CourtResult? _precheck(GameState s, PowerState? p, double cost) {
    if (p == null) return const CourtResult(false, 'قوة غير معروفة');
    if (p.dissolved) return CourtResult(false, '${p.name} محلولة أصلا');
    if (s.courtActions <= 0) return const CourtResult(false, 'استنفدت إجراءات الديوان لنصف السنة هذا');
    if (s.treasury < cost) return const CourtResult(false, 'الخزينة لا تكفي');
    return null;
  }

  static bool hasProject(GameState s, String key) => s.projects.any((p) => p.power == key);

  static void _pay(GameState s, double cost, String log) {
    s.treasury -= cost;
    s.courtActions -= 1;
    s.courtLog.add(log);
  }

  static CourtResult appease(GameState s, String key) {
    final p = s.powers[key];
    final cost = costShare(s, appeaseShare);
    final bad = _precheck(s, p, cost);
    if (bad != null) return bad;
    p!.satisfaction = clampD(p.satisfaction + 8, 0, 100);
    _pay(s, cost, 'ترضية ${p.name} بالعطايا والرواتب');
    return CourtResult(true, 'رضا ${p.name} ارتفع');
  }

  static CourtResult startProject(GameState s, String key, String kind) {
    final p = s.powers[key];
    final share = kind == 'reform' ? reformShare : (kind == 'contain' ? containShare : mergeShare);
    final cost = costShare(s, share);
    final bad = _precheck(s, p, cost);
    if (bad != null) return bad;
    if (hasProject(s, key)) {
      return CourtResult(false, 'لـ${p!.name} مشروع جار بالفعل');
    }
    final halves = kind == 'reform' ? 6 : (kind == 'contain' ? 8 : 5);
    s.projects.add(PowerProject(key, kind, halves));
    _pay(s, cost, 'بدء مشروع ${PowerProject.kindLabels[kind]} ${p!.name}');
    return CourtResult(true, 'بدأ مشروع ${PowerProject.kindLabels[kind]} ${p.name} ويستغرق ${halves ~/ 2 + halves % 2} سنوات تقريبا');
  }

  /// حل قوة بقرار الديوان (يكلف إجراء ومالا).
  static CourtResult dissolve(GameState s, String key) {
    final p = s.powers[key];
    final cost = costShare(s, dissolveShare);
    final bad = _precheck(s, p, cost);
    if (bad != null) return bad;
    final backlash = _dissolveCore(s, p!, rngFor(s, 977 + stableHash(key) % 97));
    _pay(s, cost, backlash ? 'محاولة حل ${p.name} فشلت وارتدت علينا' : 'حل ${p.name}');
    return backlash
        ? CourtResult(false, 'ارتدت محاولة حل ${p.name}: تمرد وخسارة هيبة')
        : CourtResult(true, 'حُلت ${p.name} نهائيا');
  }

  /// حل قوة بقرار من خيار ذكاء اصطناعي (بلا تكلفة إجراء). يعيد وصفا للنتيجة.
  static String dissolveFromDecision(GameState s, String key) {
    final p = s.powers[key];
    if (p == null || p.dissolved) return '';
    final backlash = _dissolveCore(s, p, rngFor(s, 977 + stableHash(key) % 97));
    return backlash
        ? 'تمردت ${p.name} على قرار حلها ونجت منه جزئيا'
        : 'حُلت ${p.name} بقرار السلطان';
  }

  /// true = ارتداد. خطر فوق 70 يعني نصف احتمال الارتداد.
  static bool _dissolveCore(GameState s, PowerState p, Random rng) {
    final backlash = p.danger > 70 && rng.nextDouble() < 0.5;
    if (backlash) {
      s.stab.shift('political', -6);
      s.stab.shift('military', -5);
      s.legitimacy = (s.legitimacy - 6).clamp(0, 100).toInt();
      s.army = (s.army - 3).clamp(0, 100).toInt();
      p.influence = clampD(p.influence * 0.6, 0, 100);
      p.satisfaction = clampD(p.satisfaction - 10, 0, 100);
      return true;
    }
    p.dissolved = true;
    p.influence = clampD(p.influence * 0.1, 0, 100);
    s.projects.removeWhere((pr) => pr.power == p.key);
    s.stab.shift('political', -2);
    s.stab.shift('regional', -1);
    return false;
  }

  /// نسبة تقريبية لنجاح الحل (للعرض في الواجهة).
  static String dissolveRisk(PowerState p) => p.danger > 70 ? 'خطر مرتفع' : 'خطر منخفض';

  /// تأكيد أن الأنظمة تتفق على الرقم الكلي (يستعمله الاختبار).
  static double averageDanger(GameState s) => StabilityRules.averageDanger(s);
}
