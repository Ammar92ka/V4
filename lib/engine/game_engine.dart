import '../data/projects_catalog.dart';
import '../models/game_state.dart';
import '../models/round_plan.dart';
import '../models/systems.dart';
import '../services/debt.dart';
import '../services/deep_economy.dart';
import '../services/diplomacy.dart';
import '../services/economy.dart';
import '../services/foreign.dart';
import '../services/powers.dart';
import '../services/projects.dart';
import '../services/provinces.dart';
import '../services/spies_climate.dart';
import '../services/stability.dart';
import '../services/wars.dart';

enum EndingType { deposed, collapse, bankruptcy, conquest, survived, dismembered}

class Ending {
  final EndingType type;
  final String title;
  final String description;
  const Ending(this.type, this.title, this.description);

  bool get isVictory => type == EndingType.survived;
}

/// تقرير نصف السنة بعد تنفيذ قرارات الجولة.
class HalfYearReport {
  final int round;
  final String period;
  final double revenue;
  final double spending;
  final double interest;
  final double oneTimeCosts;
  final double loans;
  final double emergencyBorrowed;
  final List<String> dueNotes;
  final Map<String, int> indicatorChanges;
  final double treasuryAfter;
  final double debtAfter;
  final Ending? ending;

  /// مبلغ الدين الذي سُدد فعلا هذا النصف.
  final double repaid;

  /// أحداث النصف: مناخ ومؤامرات وعلاقات وتجسس وتقارير استخبارات.
  final List<String> events;

  /// إجراءات الديوان التي نفذها اللاعب في هذا النصف.
  final List<String> courtLog;

  /// قسط المشروع القومي المدفوع، وكلفة الحروب، وما حصلته إدارة الديون العامة.
  final double projectSpend;
  final double warSpend;
  final double dadPaid;

  const HalfYearReport({
    required this.round,
    required this.period,
    required this.revenue,
    required this.spending,
    required this.interest,
    required this.oneTimeCosts,
    required this.loans,
    required this.emergencyBorrowed,
    required this.dueNotes,
    required this.indicatorChanges,
    required this.treasuryAfter,
    required this.debtAfter,
    this.ending,
    this.repaid = 0,
    this.events = const [],
    this.courtLog = const [],
    this.projectSpend = 0,
    this.warSpend = 0,
    this.dadPaid = 0,
  });

  double get net => revenue - spending - interest - warSpend - dadPaid - projectSpend;

  /// ملخص نصي مضغوط يرسل للذكاء الاصطناعي في الجولة التالية (بالملايين لتوفير التوكنات).
  String toPromptText() {
    String m(double v) => '${(v / 1e6).toStringAsFixed(2)}م';
    final changes = indicatorChanges.entries
        .where((e) => e.value != 0)
        .map((e) => '${e.key} ${e.value > 0 ? '+' : ''}${e.value}')
        .join('، ');
    final buf = StringBuffer()
      ..write('تقرير $period: إيراد ${m(revenue)}، نفقات ${m(spending)}، فوائد ${m(interest)}')
      ..write('، صافي ${m(net)}، قرارات ${m(oneTimeCosts)}');
    if (warSpend > 0) buf.write('، نفقات حرب ${m(warSpend)}');
    if (projectSpend > 0) buf.write('، مشروع قومي ${m(projectSpend)}');
    if (dadPaid > 0) buf.write('، إدارة الديون ${m(dadPaid)}');
    if (loans > 0) buf.write('، قروض ${m(loans)}');
    if (repaid > 0) buf.write('، سداد دين ${m(repaid)}');
    if (emergencyBorrowed > 0) buf.write('، اقتراض طارئ ${m(emergencyBorrowed)}');
    buf.write('.');
    if (changes.isNotEmpty) buf.write(' المؤشرات: $changes.');
    if (courtLog.isNotEmpty) buf.write(' إجراءات السلطان: ${courtLog.join('؛ ')}.');
    if (events.isNotEmpty) buf.write(' أحداث: ${events.take(8).join('؛ ')}.');
    if (dueNotes.isNotEmpty) buf.write(' آثار ظهرت الآن: ${dueNotes.join('؛ ')}.');
    return buf.toString();
  }
}

/// محرك اللعبة. لا يعرف شيئا عن الواجهة ولا عن الذكاء الاصطناعي:
/// يستقبل جولة جاهزة واختيارات اللاعب ويحسب النتائج بقواعد ثابتة.
class GameEngine {
  static const int startYear = 1800;
  static const int endYear = 1910;

  /// عدد أنصاف السنوات في الحملة (1800 إلى 1910 شاملة).
  static int get totalRounds => (endYear - startYear + 1) * 2;

  static int yearOf(int round) => startYear + round ~/ 2;

  static String halfLabel(int round) =>
      round % 2 == 0 ? 'كانون الثاني - حزيران' : 'تموز - كانون الأول';

  /// مثال: "تموز - كانون الأول 1812".
  static String periodLabel(int round) => '${halfLabel(round)} ${yearOf(round)}';

  static const int _legitimacyLossAt = 15;
  static const int _stabilityLossAt = 12;

  /// الانهيار أيضا إذا هبط ثلاثة أبعاد من الستة إلى هذا الحد، ولو بقي المتوسط مقبولا.
  static const double _brokenDimension = 8;

  /// شروط النهاية. الخسارة لها الأولوية، والنجاة عند انتهاء السنوات.
  Ending? evaluate(GameState s) {
    if (s.legitimacy <= _legitimacyLossAt) {
      return const Ending(
        EndingType.deposed,
        'خُلعت عن العرش',
        'فقدت ثقة العلماء والجند وكبار رجال الدولة، فاجتمعوا على خلعك وأعلنوا سلطانا جديدا.',
      );
    }
    if (s.stability <= _stabilityLossAt || s.stab.countBelow(_brokenDimension) >= 3) {
      return const Ending(
        EndingType.collapse,
        'انهيار النظام',
        'عمّت الفوضى والثورات الولايات والعاصمة، وانفرط عقد الدولة قبل أن تستعيد زمامها.',
      );
    }
    if (EconomyRules.debtRatio(s.debt, s.budget) >= EconomyRules.bankruptcyRatio) {
      return const Ending(
        EndingType.bankruptcy,
        'إفلاس الدولة',
        'عجزت الخزينة عن خدمة الديون، فتدخل الدائنون الأجانب في مالية الدولة وصارت قراراتها رهينة لهم.',
      );
    }
    if (s.army <= 8 && s.foreign <= 12) {
      return const Ending(
        EndingType.conquest,
        'تقاسم الدول الكبرى للأراضي',
        'ضعف الجيش وغابت المكانة الدولية، فاقتطعت القوى الكبرى الولايات واحدة بعد أخرى.',
      );
    }
    if (s.econ.activeWeight < ProvinceRules.dismemberedBelow) {
      return const Ending(
        EndingType.dismembered,
        'تفككت الإمبراطورية',
        'انفصلت الولايات واحدة بعد أخرى حتى لم يبق للسلطان إلا العاصمة وما حولها، وتحولت الدولة إلى دويلة.',
      );
    }
    if (s.round >= totalRounds) {
      final avg = (s.legitimacy + s.stability + s.army + s.foreign + s.education) / 5;
      final ratio = EconomyRules.debtRatio(s.debt, s.budget);
      if (avg >= 70 && ratio < 1.5) {
        return Ending(
          EndingType.survived,
          'إمبراطورية مزدهرة',
          'بلغت عام $endYear والدولة قوية ومحدثة، وصارت لها كلمة بين الكبار.',
        );
      }
      if (avg >= 50 && ratio < 3) {
        return Ending(
          EndingType.survived,
          'دولة متماسكة',
          'بلغت عام $endYear والدولة ما زالت متماسكة رغم الأزمات، وأمامها طريق إصلاح طويل.',
        );
      }
      return Ending(
        EndingType.survived,
        'نجوت بالكاد',
        'بلغت عام $endYear والدولة مثقلة بالديون والضعف، لكنها ما زالت قائمة.',
      );
    }
    return null;
  }

  int _ind(int v) => v.clamp(0, 100).toInt();

  /// الاستقرار يتوزع بالتساوي على أبعاده الستة.
  void _applyEffects(GameState s, Effects e) {
    final k = s.diff.losses;
    int adj(int v) => v < 0 ? (v * k).round() : v;
    s.legitimacy = _ind(s.legitimacy + adj(e.legitimacy));
    if (e.stability != 0) s.stab.shiftAll(adj(e.stability).toDouble());
    s.army = _ind(s.army + adj(e.army));
    s.foreign = _ind(s.foreign + adj(e.foreign));
    s.education = _ind(s.education + adj(e.education));
  }

  /// تغيير بند في الميزانية مع أثره على الولايات والفساد.
  void _changeLine(GameState s, String line, double delta) {
    DeepEconomyRules.onLineChange(s, line, delta);
    s.budget.change(line, delta);
  }

  Map<String, int> _snapshot(GameState s) => {
    'الشرعية': s.legitimacy,
    'الاستقرار': s.stability,
    'الجيش': s.army,
    'المكانة الدولية': s.foreign,
    'التعليم': s.education,
  };

  /// يسدد من الدين من الخزينة. يعيد المبلغ المسدد فعلا.
  double repayDebt(GameState s, double amount) => DebtRules.repay(s, amount);

  /// ينفذ قرارات الجولة الحالية ويدخل نصف السنة التالي.
  /// يشترط أن تكون الجولة جاهزة وأن يكون اللاعب قد اختار في القرارات الثلاثة.
  HalfYearReport resolveRound(GameState s) {
    final plan = s.plan;
    if (plan == null || !s.hasAllPicks) {
      throw StateError('الجولة غير جاهزة للتنفيذ');
    }
    final before = _snapshot(s);
    final finishedRound = s.round;
    final courtLog = List<String>.from(s.courtLog);
    final events = <String>[];
    var costs = 0.0;
    var loans = 0.0;

    // 1) قرارات اللاعب
    for (var i = 0; i < 3; i++) {
      final decision = plan.decisions[i];
      final option = decision.options[s.picks[i]!];
      costs += option.cost;
      loans += option.loan;
      s.treasury -= option.cost;
      s.treasury += option.loan;
      DebtRules.addLoan(s, option.loan);
      _applyEffects(s, option.now);
      DiplomacyRules.applyRelations(s, option.relations);
      option.powerMood.forEach((k, d) {
        final p = s.powers[k];
        if (p != null && !p.dissolved) p.satisfaction = clampD(p.satisfaction + d, 0, 100);
      });
      if (option.dissolve.isNotEmpty) {
        final msg = PowerRules.dissolveFromDecision(s, option.dissolve);
        if (msg.isNotEmpty) events.add(msg);
      }
      if (option.war.isNotEmpty) {
        final msg = WarRules.declare(s, option.war, byUs: true);
        if (msg.isNotEmpty) events.add(msg);
      }
      if (option.peace.isNotEmpty) {
        final msg = WarRules.peaceFromDecision(s, option.peace);
        if (msg.isNotEmpty) events.add(msg);
      }
      if (option.project.isNotEmpty) {
        final d = projectDef(option.project);
        if (d != null) {
          final r = ProjectRules.start(
            s,
            option.project,
            (d.minHalves + d.maxHalves) ~/ 2,
            viaDecision: true,
          );
          if (r.ok) events.add(r.message);
        }
      }
      if (!option.later.isZero || option.lineChanges.isNotEmpty) {
        if (option.delay <= 0) {
          _applyEffects(s, option.later);
          for (final c in option.lineChanges) {
            _changeLine(s, c.line, c.delta);
          }
        } else {
          s.pending.add(
            PendingEffect(
              dueRound: finishedRound + option.delay,
              effects: option.later,
              lines: option.lineChanges,
              source: '${decision.title}: ${_short(option.text)}',
            ),
          );
        }
      }
      s.history.add(
        HistoryEntry(
          round: finishedRound,
          category: decision.category.label,
          title: decision.title,
          choice: option.text,
          result: option.result,
        ),
      );
    }

    // 2) مناخ نصف السنة (قبل الجباية لأن المحصول يؤثر فيها)
    events.addAll(ClimateRules.step(s));

    // 3) ميزانية نصف السنة
    final revenue =
        EconomyRules.halfYearRevenue(s.budget, s.stability, econ: s.econ) * s.diff.revenue;
    final spending = EconomyRules.halfYearSpending(s.budget);
    final interest = DebtRules.halfYearInterest(s);
    final warSpend = WarRules.costs(s);
    final dadPaid = DebtRules.dadPayment(s, revenue);
    final net = revenue - spending - interest - warSpend - dadPaid;
    s.treasury += net;

    // قسط المشروع القومي: يدفع إن وجد في الخزينة وإلا يتعثر المشروع
    final project = ProjectRules.fund(s);
    events.addAll(project.notes);

    // 4) اقتراض طارئ عند نفاد الخزينة (رواتب متأخرة تضر بالجيش والاستقرار)
    var emergency = 0.0;
    if (s.treasury < 0) {
      emergency = -s.treasury * (1 + EconomyRules.emergencyLoanFee);
      s.debt += emergency;
      s.treasury = 0;
      s.legitimacy = _ind(s.legitimacy - 1);
      s.stab.shiftAll(-1);
      s.army = _ind(s.army - 2);
    }
    s.emergencyStreak = emergency > 0 ? s.emergencyStreak + 1 : 0;

    // 5) تسديد دين اختاره اللاعب (من الفائض فقط؛ لا يسبب اقتراضا طارئا)
    final repaid = repayDebt(s, s.repay);
    s.repay = 0;

    // 6) الأنظمة العميقة
    final ratio = EconomyRules.debtRatio(s.debt, s.budget);
    events.addAll(DeepEconomyRules.step(s, net: net));
    events.addAll(StabilityRules.step(s, debtRatio: ratio, emergency: emergency > 0));
    events.addAll(PowerRules.step(s, emergency: emergency > 0));
    events.addAll(DiplomacyRules.step(s));
    ForeignRules.step(s);
    events.addAll(WarRules.step(s));
    events.addAll(ProvinceRules.step(s));
    events.addAll(DebtRules.step(s));
    events.addAll(SpyRules.step(s));

    // 7) انجراف الجيش والتعليم بحسب الإنفاق
    final totalRevenue = s.budget.totalRevenue;
    if (totalRevenue > 0) {
      s.army = _ind(s.army + EconomyRules.armyDrift(s.budget.lineValue('army') / totalRevenue));
      s.education = _ind(
        s.education + EconomyRules.educationDrift(s.budget.lineValue('civil') / totalRevenue),
      );
    }

    // 8) نمو اسمي ثم دخول نصف السنة التالي وظهور الآثار المؤجلة
    DeepEconomyRules.applyNominalGrowth(s);
    s.round += 1;
    final due = <String>[];
    final stillPending = <PendingEffect>[];
    for (final p in s.pending) {
      if (p.dueRound <= s.round) {
        _applyEffects(s, p.effects);
        for (final c in p.lines) {
          _changeLine(s, c.line, c.delta);
        }
        due.add(p.source);
      } else {
        stillPending.add(p);
      }
    }
    s.pending = stillPending;

    // لقطة للرسوم البيانية
    s.series.add(
      StatPoint(
        round: s.round,
        treasury: s.treasury,
        debt: s.debt,
        revenue: s.budget.totalRevenue,
        legitimacy: s.legitimacy,
        stability: s.stability,
        army: s.army,
        foreign: s.foreign,
        education: s.education,
        population: s.demog.population,
        literacy: s.demog.literacy,
        inflation: s.econ.inflation,
      ),
    );
    if (s.series.length > 460) s.series.removeRange(0, s.series.length - 460);

    // 9) تنظيف الجولة المنتهية وفتح نصف سنة جديد
    s.plan = null;
    s.picks = <int?>[null, null, null];
    s.courtActions = 2;
    s.courtLog = <String>[];
    s.events = events.take(16).toList();

    final after = _snapshot(s);
    final changes = <String, int>{
      for (final k in before.keys) k: after[k]! - before[k]!,
    };
    final report = HalfYearReport(
      round: finishedRound,
      period: periodLabel(finishedRound),
      revenue: revenue,
      spending: spending,
      interest: interest,
      oneTimeCosts: costs,
      loans: loans,
      emergencyBorrowed: emergency,
      dueNotes: due,
      indicatorChanges: changes,
      treasuryAfter: s.treasury,
      debtAfter: s.debt,
      ending: evaluate(s),
      repaid: repaid,
      events: events,
      courtLog: courtLog,
      projectSpend: project.spent,
      warSpend: warSpend,
      dadPaid: dadPaid,
    );
    s.lastReport = report.toPromptText();
    return report;
  }

  String _short(String text) =>
      text.length <= 60 ? text : '${text.substring(0, 60)}...';
}
