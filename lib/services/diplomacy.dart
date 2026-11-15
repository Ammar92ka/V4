import '../models/game_state.dart';
import '../models/round_plan.dart';
import '../models/systems.dart';
import 'sim_common.dart';

/// الدبلوماسية: العلاقات، السفارات، المعاهدات، وسقف الاقتراض الخارجي.
/// تكاليف السفارات وشبكات التجسس تدخل بند "الإدارة" في الميزانية فتظهر في الحسابات.
class DiplomacyRules {
  DiplomacyRules._();

  static const double embassyOpenShare = 0.02;
  static const double embassyUpkeepShare = 0.01;
  static const double giftShare = 0.010;
  static const double treatyShare = 0.012;
  static const double treatyCustomsGain = 0.015;
  static const int treatyCooldown = 20;

  /// كلفة تشغيل شبكة تجسس خارجية حسب المستوى (نسبة من الإيراد السنوي).
  static const List<double> spyUpkeep = [0, 0.012, 0.030];
  static const List<double> domesticUpkeep = [0, 0.015, 0.035];
  static const double spyRecruitShare = 0.010;

  /// متوسط علاقات الدائنين الثلاثة عند البدء.
  static const double _creditRef = 48;

  /// معامل الاقتراض: علاقات الدائنين الجيدة توسع سقف القروض والسيئة تضيقه.
  static double creditFactor(GameState s) {
    final lenders = ['britain', 'france', 'austria'];
    var sum = 0.0;
    for (final k in lenders) {
      sum += s.countries[k]?.relation ?? _creditRef;
    }
    final avg = sum / lenders.length;
    return clampD(1 + (avg - _creditRef) / 100, 0.6, 1.25);
  }

  static String relationLabel(double r) {
    if (r < 25) return 'عدائية';
    if (r < 40) return 'متوترة';
    if (r < 60) return 'محايدة';
    if (r < 80) return 'ودية';
    return 'حليفة';
  }

  /// أثر خيار من الذكاء الاصطناعي على العلاقات.
  static void applyRelations(GameState s, Map<String, int> deltas) {
    deltas.forEach((k, d) {
      final c = s.countries[k];
      if (c != null) c.relation = clampD(c.relation + d, 0, 100);
    });
  }

  /// خطوة نصف السنة: ميل العلاقات وتحذيرات الحرب.
  static List<String> step(GameState s) {
    final notes = <String>[];
    for (final c in s.countries.values) {
      if (c.embassy) {
        if (c.relation < 60) c.relation = clampD(c.relation + 0.3, 0, 100);
      } else if (c.relation > 45) {
        c.relation = clampD(c.relation - 1, 45, 100);
      } else if (c.relation < 45) {
        c.relation = clampD(c.relation + 1, 0, 45);
      }
    }
    if (s.army < 30) {
      s.countries['russia']?.relation = clampD((s.countries['russia']?.relation ?? 0) - 1, 0, 100);
      s.countries['austria']?.relation = clampD((s.countries['austria']?.relation ?? 0) - 0.5, 0, 100);
    }
    if (s.foreign > 65) {
      for (final c in s.countries.values) {
        c.relation = clampD(c.relation + 0.3, 0, 100);
      }
    }
    for (final c in s.countries.values) {
      if (c.relation < 20) notes.add('علاقاتنا بـ${c.name} في أسوأ حالاتها وخطر الحرب قائم');
    }
    return notes;
  }

  // ───────────── السفارات (بلا إجراء، بكلفة مالية) ─────────────

  static CourtResult openEmbassy(GameState s, String key) {
    final c = s.countries[key];
    if (c == null) return const CourtResult(false, 'دولة غير معروفة');
    if (c.embassy) return CourtResult(false, 'لنا سفارة في ${c.name} أصلا');
    final cost = costShare(s, embassyOpenShare);
    if (s.treasury < cost) return const CourtResult(false, 'الخزينة لا تكفي');
    s.treasury -= cost;
    s.budget.change('admin', costShare(s, embassyUpkeepShare));
    c.embassy = true;
    s.courtLog.add('افتتاح سفارة دائمة في ${c.name}');
    return CourtResult(true, 'افتتحت سفارة في ${c.name}');
  }

  static CourtResult closeEmbassy(GameState s, String key) {
    final c = s.countries[key];
    if (c == null) return const CourtResult(false, 'دولة غير معروفة');
    if (!c.embassy) return CourtResult(false, 'لا سفارة لنا في ${c.name}');
    s.budget.change('admin', -costShare(s, embassyUpkeepShare));
    c.embassy = false;
    c.relation = clampD(c.relation - 4, 0, 100);
    s.courtLog.add('إغلاق السفارة في ${c.name}');
    return CourtResult(true, 'أغلقت السفارة في ${c.name} وتضررت العلاقة قليلا');
  }

  // ───────────── التجسس (بلا إجراء، بكلفة مالية) ─────────────

  static CourtResult setSpyLevel(GameState s, String key, int level) {
    final c = s.countries[key];
    if (c == null) return const CourtResult(false, 'دولة غير معروفة');
    final to = level.clamp(0, 2).toInt();
    if (to == c.spy) return const CourtResult(true, 'لا تغيير');
    if (to > c.spy) {
      final cost = costShare(s, spyRecruitShare) * (to - c.spy);
      if (s.treasury < cost) return const CourtResult(false, 'الخزينة لا تكفي لتجنيد العملاء');
      s.treasury -= cost;
    }
    s.budget.change('admin', costShare(s, spyUpkeep[to] - spyUpkeep[c.spy]));
    s.courtLog.add('شبكة التجسس على ${c.name}: مستوى $to');
    c.spy = to;
    return CourtResult(true, 'شبكة التجسس على ${c.name} صارت مستوى $to');
  }

  static CourtResult setDomesticSpy(GameState s, int level) {
    final to = level.clamp(0, 2).toInt();
    if (to == s.domesticSpy) return const CourtResult(true, 'لا تغيير');
    if (to > s.domesticSpy) {
      final cost = costShare(s, spyRecruitShare) * (to - s.domesticSpy);
      if (s.treasury < cost) return const CourtResult(false, 'الخزينة لا تكفي لتجنيد العملاء');
      s.treasury -= cost;
    }
    s.budget.change('admin', costShare(s, domesticUpkeep[to] - domesticUpkeep[s.domesticSpy]));
    s.courtLog.add('الاستخبارات الداخلية: مستوى $to');
    s.domesticSpy = to;
    return CourtResult(true, 'الاستخبارات الداخلية صارت مستوى $to');
  }

  // ───────────── إجراءات تستهلك من إجراءات الديوان ─────────────

  static CourtResult _checkAction(GameState s, CountryState? c, double cost) {
    if (c == null) return const CourtResult(false, 'دولة غير معروفة');
    if (s.courtActions <= 0) return const CourtResult(false, 'استنفدت إجراءات الديوان لنصف السنة هذا');
    if (s.treasury < cost) return const CourtResult(false, 'الخزينة لا تكفي');
    return const CourtResult(true, '');
  }

  static CourtResult gift(GameState s, String key) {
    final c = s.countries[key];
    final cost = costShare(s, giftShare);
    final chk = _checkAction(s, c, cost);
    if (!chk.ok) return chk;
    s.treasury -= cost;
    s.courtActions -= 1;
    c!.relation = clampD(c.relation + 6, 0, 100);
    s.courtLog.add('هدايا دبلوماسية إلى ${c.name}');
    return CourtResult(true, 'تحسنت علاقتنا بـ${c.name}');
  }

  static CourtResult tradeTreaty(GameState s, String key) {
    final c = s.countries[key];
    final cost = costShare(s, treatyShare);
    final chk = _checkAction(s, c, cost);
    if (!chk.ok) return chk;
    if (c!.relation < 40) return CourtResult(false, 'علاقتنا بـ${c.name} أسوأ من أن تقبل معاهدة');
    if (s.round - c.lastTreaty < treatyCooldown) {
      return CourtResult(false, 'معاهدتنا مع ${c.name} ما زالت سارية');
    }
    s.treasury -= cost;
    s.courtActions -= 1;
    c.lastTreaty = s.round;
    c.relation = clampD(c.relation + 8, 0, 100);
    if (key == 'britain') {
      s.countries['france']?.relation = clampD((s.countries['france']?.relation ?? 0) - 5, 0, 100);
    } else if (key == 'france') {
      s.countries['britain']?.relation = clampD((s.countries['britain']?.relation ?? 0) - 5, 0, 100);
    }
    s.pending.add(
      PendingEffect(
        dueRound: s.round + 2,
        lines: [LineChange('customs', costShare(s, treatyCustomsGain))],
        source: 'معاهدة تجارية مع ${c.name}',
      ),
    );
    s.courtLog.add('معاهدة تجارية مع ${c.name}');
    return CourtResult(true, 'وُقعت معاهدة تجارية مع ${c.name}؛ تظهر عوائدها بعد سنة');
  }
}
