import '../models/budget.dart';
import '../models/game_state.dart';
import '../models/round_plan.dart';
import '../services/diplomacy.dart';

/// معايرة ما يكتبه الذكاء الاصطناعي مع الواقع الاقتصادي للحملة.
/// النص حر للذكاء الاصطناعي، أما الأرقام فتقيدها حدود نسبية إلى حجم ميزانية الدولة
/// في لحظة الجولة، فلا يخرج قرار واحد عن المعقول ولا يكسر التوازن.
class Calibrator {
  Calibrator._();

  /// أقصى مصروف لخيار واحد، كنسبة من الإيراد السنوي.
  static const double maxCostShare = 0.60;

  /// أقصى قرض لخيار واحد، كنسبة من الإيراد السنوي.
  static const double maxLoanShare = 1.00;

  /// أقصى تغيير سنوي في بند واحد، كنسبة من الإيراد السنوي.
  static const double maxLineShare = 0.15;

  static const int maxNow = 8;
  static const int maxLater = 12;
  static const int maxDelay = 10;
  static const int maxLineChanges = 3;

  /// أقصى أثر فوري لخيار على علاقة دولة، وعلى رضا قوة، وعدد الدول/القوى في الخيار.
  static const int maxRelation = 8;
  static const int maxPowerMood = 10;
  static const int maxMapKeys = 3;

  /// أقصى مجموع للمكاسب الموجبة في خيار واحد (فوري ومؤجل) حتى لا يوجد خيار بلا ثمن.
  static const int maxTotalGain = 16;

  static const int maxTitle = 90;
  static const int maxScene = 800;
  static const int maxDilemma = 500;
  static const int maxOptionText = 420;
  static const int maxResult = 500;
  static const int maxReaction = 420;
  static const int maxNote = 300;
  static const int maxBriefing = 1000;
  static const int maxChronicle = 700;

  static RoundPlan calibrate(RoundPlan raw, GameState s) {
    final revenue = s.budget.totalRevenue;
    final credit = DiplomacyRules.creditFactor(s);
    return RoundPlan(
      headline: _cut(raw.headline, maxTitle),
      briefing: _cut(raw.briefing, maxBriefing),
      chronicle: _cut(raw.chronicle, maxChronicle),
      world: raw.world,
      decisions: [
        for (final d in raw.decisions)
          Decision(
            category: d.category,
            title: _cut(d.title, maxTitle),
            place: _cut(d.place, 70),
            scene: _cut(d.scene, maxScene),
            dilemma: _cut(d.dilemma, maxDilemma),
            options: [
              for (final o in d.options) calibrateOption(o, revenue, creditFactor: credit),
            ],
          ),
      ],
    );
  }

  /// [creditFactor] يضيق سقف القروض أو يوسعه بحسب علاقات الدائنين (1.0 = بلا تعديل).
  static DecisionOption calibrateOption(
    DecisionOption o,
    double annualRevenue, {
    double creditFactor = 1.0,
  }) {
    var changed = false;
    double clampMoney(double v, double max) {
      final c = v.isFinite ? v.clamp(0.0, max).toDouble() : 0.0;
      if ((c - v).abs() > max * 0.005) changed = true;
      return c.roundToDouble();
    }

    final cost = clampMoney(o.cost, annualRevenue * maxCostShare);
    final loan = clampMoney(o.loan, annualRevenue * maxLoanShare * creditFactor);

    var now = o.now.clampTo(maxNow);
    var later = o.later.clampTo(maxLater);
    if (_differs(now, o.now) || _differs(later, o.later)) changed = true;

    // لا خيار بلا ثمن: المكاسب الموجبة لها سقف.
    final gain = _positiveSum(now) + _positiveSum(later);
    if (gain > maxTotalGain) {
      final k = maxTotalGain / gain;
      now = _scalePositive(now, k);
      later = _scalePositive(later, k);
      changed = true;
    }

    // تغييرات الميزانية: بنود معروفة فقط، ودمج المكرر، وحد أقصى للعدد والحجم.
    final merged = <String, double>{};
    for (final c in o.lineChanges) {
      if (!isBudgetLine(c.line)) {
        changed = true;
        continue;
      }
      merged[c.line] = (merged[c.line] ?? 0) + c.delta;
    }
    final lines = <LineChange>[];
    final limit = annualRevenue * maxLineShare;
    for (final e in merged.entries) {
      if (lines.length >= maxLineChanges) {
        changed = true;
        break;
      }
      final v = e.value.isFinite ? e.value.clamp(-limit, limit).toDouble() : 0.0;
      if ((v - e.value).abs() > limit * 0.005) changed = true;
      if (v.abs() >= 1) lines.add(LineChange(e.key, v.roundToDouble()));
    }

    // الإيراد الجديد لا يأتي فورا: الجباية والإصلاح يحتاجان وقتا.
    var delay = o.delay.clamp(0, maxDelay).toInt();
    if (delay != o.delay) changed = true;
    final raisesRevenue = lines.any((c) => isRevenueLine(c.line) && c.delta > 0);
    if (raisesRevenue && delay < 1) {
      delay = 1;
      changed = true;
    }

    // علاقات الدول ورضا القوى: حدود الحجم وعدد المفاتيح
    Map<String, int> limitMap(Map<String, int> raw, int max) {
      final out = <String, int>{};
      for (final e in raw.entries) {
        if (out.length >= maxMapKeys) {
          changed = true;
          break;
        }
        final v = e.value.clamp(-max, max).toInt();
        if (v != e.value) changed = true;
        if (v != 0) out[e.key] = v;
      }
      return out;
    }

    final relations = limitMap(o.relations, maxRelation);
    final powerMood = limitMap(o.powerMood, maxPowerMood);

    return DecisionOption(
      text: _cut(o.text, maxOptionText),
      result: _cut(o.result, maxResult),
      reaction: _cut(o.reaction, maxReaction),
      note: _cut(o.note, maxNote),
      cost: cost,
      loan: loan,
      now: now,
      later: later,
      delay: delay,
      lineChanges: lines,
      relations: relations,
      powerMood: powerMood,
      dissolve: o.dissolve,
      war: o.war,
      peace: o.peace,
      project: o.project,
      calibrated: changed,
    );
  }

  static bool _differs(Effects a, Effects b) =>
      a.legitimacy != b.legitimacy ||
      a.stability != b.stability ||
      a.army != b.army ||
      a.foreign != b.foreign ||
      a.education != b.education;

  static int _positiveSum(Effects e) =>
      [e.legitimacy, e.stability, e.army, e.foreign, e.education]
          .where((v) => v > 0)
          .fold(0, (a, b) => a + b);

  static Effects _scalePositive(Effects e, double k) {
    int f(int v) => v > 0 ? (v * k).floor() : v;
    return Effects(
      legitimacy: f(e.legitimacy),
      stability: f(e.stability),
      army: f(e.army),
      foreign: f(e.foreign),
      education: f(e.education),
    );
  }

  static String _cut(String s, int max) {
    final t = s.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1).trimRight()}…';
  }
}
