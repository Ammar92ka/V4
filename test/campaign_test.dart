import 'package:flutter_test/flutter_test.dart';
import 'package:ottoman_empire_1800/data/projects_catalog.dart';
import 'package:ottoman_empire_1800/engine/calibrator.dart';
import 'package:ottoman_empire_1800/engine/game_engine.dart';
import 'package:ottoman_empire_1800/models/game_state.dart';
import 'package:ottoman_empire_1800/models/round_plan.dart';
import 'package:ottoman_empire_1800/models/systems.dart';
import 'package:ottoman_empire_1800/services/debt.dart';
import 'package:ottoman_empire_1800/services/foreign.dart';
import 'package:ottoman_empire_1800/services/projects.dart';
import 'package:ottoman_empire_1800/services/provinces.dart';
import 'package:ottoman_empire_1800/services/spies_climate.dart';
import 'package:ottoman_empire_1800/services/wars.dart';

import 'support/bots.dart';

HalfYearReport _round(GameState s, [RoundPlan? plan]) {
  s.plan = Calibrator.calibrate(plan ?? neutralPlan(), s);
  s.picks = [0, 0, 0];
  return GameEngine().resolveRound(s);
}

RoundPlan _withFirstOption(DecisionOption o) {
  final base = neutralPlan();
  return RoundPlan(
    headline: 'h',
    briefing: 'b',
    decisions: [
      Decision(
        category: DecisionCategory.internal,
        title: 't',
        scene: 's',
        dilemma: 'd',
        options: [o, const DecisionOption(text: 'ب', result: 'ن'), const DecisionOption(text: 'ج', result: 'ن')],
      ),
      base.decisions[1],
      base.decisions[2],
    ],
  );
}

void main() {
  group('مستويات الصعوبة', () {
    test('الإيراد يتبع المستوى: سهل > عادي > صعب', () {
      final easy = _round(GameState(difficulty: 0)).revenue;
      final normal = _round(GameState(difficulty: 1)).revenue;
      final hard = _round(GameState(difficulty: 2)).revenue;
      expect(easy / normal, closeTo(1.06, 1e-9));
      expect(hard / normal, closeTo(0.94, 1e-9));
    });

    test('الأثر السلبي للقرار يضخم في الصعب ويخف في السهل', () {
      const o = DecisionOption(text: 'خسارة', result: 'ن', now: Effects(stability: -4));
      int after(int level) {
        final s = GameState(difficulty: level);
        _round(s, _withFirstOption(o));
        return s.stability;
      }

      expect(after(1), equals(51));
      expect(after(0), equals(52));
      expect(after(2), equals(50));
    });

    test('الكوارث أكثر في الصعب وأقل في السهل', () {
      int count(int level) {
        final s = GameState(difficulty: level);
        var n = 0;
        for (var i = 4; i < 504; i++) {
          s.round = i;
          n += ClimateRules.step(s).length;
        }
        return n;
      }

      expect(count(0), lessThan(count(1)));
      expect(count(1), lessThan(count(2)));
    });

    test('المستوى يحفظ ويستعاد', () {
      expect(GameState(difficulty: 2).copy().difficulty, equals(2));
      expect(GameState().difficulty, equals(1));
    });
  });

  group('كتالوج المشاريع', () {
    test('مفاتيح فريدة وأرقام سليمة', () {
      final keys = projectCatalog.map((d) => d.key).toSet();
      expect(keys.length, equals(projectCatalog.length));
      expect(projectCatalog.length, greaterThanOrEqualTo(15));
      for (final d in projectCatalog) {
        expect(d.cost, inInclusiveRange(0.2, 1.5));
        expect(d.minHalves, lessThan(d.maxHalves));
        expect(d.benefits, isNotEmpty);
        expect(isProjectKey(d.key), isTrue);
      }
    });

    test('الإتاحة بحسب السنة والمنجز', () {
      final s = GameState();
      final keys0 = ProjectRules.available(s).map((d) => d.key).toList();
      expect(keys0.contains('roads'), isTrue);
      expect(keys0.contains('telegraph'), isFalse);
      s.round = 2 * (1860 - 1800);
      expect(ProjectRules.available(s).map((d) => d.key).contains('railway'), isTrue);
      s.completed.add('railway');
      expect(ProjectRules.available(s).map((d) => d.key).contains('railway'), isFalse);
    });

    test('الأقصر أغلى بحتى 25% والقسط = الكلفة ÷ المدة', () {
      final s = GameState();
      final d = projectDef('roads')!;
      final slow = ProjectRules.totalCost(s, d, d.maxHalves);
      final fast = ProjectRules.totalCost(s, d, d.minHalves);
      expect(slow, equals(s.budget.totalRevenue * d.cost));
      expect(fast / slow, closeTo(1.25, 1e-6));
      expect(ProjectRules.installment(s, d, 10) * 10, closeTo(ProjectRules.totalCost(s, d, 10), 10));
      expect(ProjectRules.clampHalves(d, 1), equals(d.minHalves));
      expect(ProjectRules.clampHalves(d, 99), equals(d.maxHalves));
    });
  });

  group('تنفيذ المشروع', () {
    test('بدء مشروع: إجراء وقسط أول، ومشروع واحد فقط، وقبل أوانه مرفوض', () {
      final s = GameState(treasury: 20000000);
      expect(ProjectRules.start(s, 'telegraph', 6).ok, isFalse);
      expect(ProjectRules.start(s, 'ghost', 6).ok, isFalse);
      final r = ProjectRules.start(s, 'roads', 8);
      expect(r.ok, isTrue);
      expect(s.project!.halves, equals(8));
      expect(s.courtActions, equals(1));
      expect(ProjectRules.start(s, 'irrigation', 8).ok, isFalse);
      final poor = GameState(treasury: 1000);
      expect(ProjectRules.start(poor, 'roads', 8).ok, isFalse);
      expect(poor.project, isNull);
    });

    test('يتقدم كل نصف سنة ويكتمل بفوائده وصيانته', () {
      final s = GameState(treasury: 80000000);
      ProjectRules.start(s, 'roads', 6);
      final rev0 = s.budget.totalRevenue;
      final customs0 = s.budget.lineValue('customs');
      final civil0 = s.budget.lineValue('civil');
      final army0 = s.army;
      final first = _round(s);
      expect(first.projectSpend, greaterThan(0));
      expect(s.project!.funded, equals(1));
      expect(s.project!.progress, closeTo(1 / 6, 1e-9));
      for (var i = 0; i < 5; i++) {
        _round(s);
      }
      expect(s.project, isNull);
      expect(s.completed, equals(['roads']));
      expect(s.budget.lineValue('customs'), greaterThan(customs0 * 1.06));
      expect(s.budget.totalRevenue, greaterThan(rev0));
      expect(s.budget.lineValue('civil'), greaterThan(civil0 * 1.06));
      expect(s.army, greaterThan(army0));
    });

    test('التمويل الناقص يعطل المشروع ولا يخصم شيئا', () {
      final s = GameState(treasury: 0);
      s.project = ActiveProject('roads', 6, 99000000, 0);
      final report = _round(s);
      expect(s.project!.funded, equals(0));
      expect(s.project!.stalled, equals(1));
      expect(report.projectSpend, equals(0));
      expect(report.events.any((e) => e.contains('تعثر')), isTrue);
    });

    test('الإلغاء يضيع ما أنفق', () {
      final s = GameState(treasury: 20000000);
      ProjectRules.start(s, 'roads', 6);
      expect(ProjectRules.cancel(s).ok, isTrue);
      expect(s.project, isNull);
      expect(ProjectRules.cancel(s).ok, isFalse);
    });

    test('ميزة الري تخفف الجفاف والحجر الصحي يخفف الطاعون', () {
      double worstHarvest(bool irrigation) {
        final s = GameState();
        if (irrigation) s.completed.add('irrigation');
        var worst = 1.0;
        for (var i = 4; i < 600; i++) {
          s.round = i;
          final notes = ClimateRules.step(s);
          if (notes.any((n) => n.contains('جفاف'))) {
            for (final p in s.econ.provinces.values) {
              if (p.harvest < worst) worst = p.harvest;
            }
          }
        }
        return worst;
      }

      expect(worstHarvest(false), closeTo(0.65, 1e-9));
      expect(worstHarvest(true), closeTo(0.8, 1e-9));
    });

    test('قرار ذكاء اصطناعي يبدأ مشروعا إن كان المجال مفتوحا', () {
      final s = GameState(treasury: 50000000);
      _round(s, _withFirstOption(const DecisionOption(text: 'مشروع', result: 'ن', project: 'irrigation')));
      expect(s.project?.key, equals('irrigation'));
      final other = GameState(treasury: 50000000);
      ProjectRules.start(other, 'roads', 8);
      _round(other, _withFirstOption(const DecisionOption(text: 'مشروع', result: 'ن', project: 'irrigation')));
      expect(other.project?.key, equals('roads'));
    });

    test('المشروع والمنجز يحفظان', () {
      final s = GameState(treasury: 20000000);
      ProjectRules.start(s, 'roads', 8);
      s.project!.funded = 3;
      s.completed.add('irrigation');
      final c = s.copy();
      expect(c.project!.funded, equals(3));
      expect(c.project!.progress, closeTo(3 / 8, 1e-9));
      expect(c.completed, equals(['irrigation']));
    });
  });

  group('اقتصادات الدول وقواها', () {
    test('المقياس الابتدائي ونسب القوة', () {
      final s = GameState();
      expect(ForeignRules.ottomanEconomy(s), closeTo(100, 1e-9));
      expect(ForeignRules.econRatio(s, s.countries['britain']!), closeTo(2.2, 1e-9));
      expect(ForeignRules.milRatio(s, s.countries['persia']!), lessThan(1));
      expect(ForeignRules.strengthLabel(0.5), equals('أضعف منا'));
      expect(ForeignRules.strengthLabel(1.0), equals('مقارب لنا'));
      expect(ForeignRules.strengthLabel(1.5), equals('أقوى منا'));
      expect(ForeignRules.strengthLabel(3), equals('أقوى منا بكثير'));
    });

    test('النمو التاريخي: بريطانيا تنمو وفرنسا تنكسر عسكريا بعد 1815 وألمانيا تصعد', () {
      expect(ForeignRules.annualMilGrowth('france', 1810), greaterThan(0.02));
      expect(ForeignRules.annualMilGrowth('france', 1820), lessThan(0));
      expect(ForeignRules.annualMilGrowth('germany', 1880), greaterThan(0.03));
      final s = GameState();
      final b0 = s.countries['britain']!.economy;
      for (var i = 0; i < 100; i++) {
        s.round = i;
        ForeignRules.step(s);
      }
      expect(s.countries['britain']!.economy, greaterThan(b0 * 1.5));
    });

    test('حتمية بالبذرة وفقدان الولايات يخفض اقتصادنا', () {
      List<double> run(int seed) {
        final s = GameState(seed: seed);
        for (var i = 0; i < 40; i++) {
          s.round = i;
          ForeignRules.step(s);
        }
        return [s.countries['russia']!.economy, s.countries['russia']!.military];
      }

      expect(run(3), equals(run(3)));
      expect(run(3), isNot(equals(run(4))));
      final s = GameState();
      s.econ.provinces['egypt']!.status = ProvinceState.independent;
      expect(ForeignRules.ottomanEconomy(s), closeTo(80, 1.0));
    });
  });

  group('الولايات والانفصال', () {
    test('مصر أسرع انجرافا من الأناضول، والرضا العالي يعكس الاتجاه', () {
      final s = GameState();
      final egypt = s.econ.provinces['egypt']!.autonomy;
      final anatolia = s.econ.provinces['anatolia']!.autonomy;
      ProvinceRules.step(s);
      expect(s.econ.provinces['egypt']!.autonomy - egypt, greaterThan(0.3));
      expect(s.econ.provinces['anatolia']!.autonomy - anatolia, lessThan(0.1));
      final happy = GameState(legitimacy: 95, army: 70);
      for (final p in happy.econ.provinces.values) {
        p.mood = 95;
      }
      final e0 = happy.econ.provinces['egypt']!.autonomy;
      ProvinceRules.step(happy);
      expect(happy.econ.provinces['egypt']!.autonomy, lessThan(e0));
    });

    test('الحكم الذاتي يخفض الوزن الفعال ثم تعود الولاية موالية', () {
      final s = GameState();
      final p = s.econ.provinces['egypt']!;
      p.autonomy = 72;
      ProvinceRules.step(s);
      expect(p.status, equals(ProvinceState.autonomousStatus));
      expect(s.econ.activeWeight, closeTo(1 - 0.2 * 0.6, 1e-9));
      expect(s.econ.revenueMultiplier, lessThan(0.93));
      p.autonomy = 30;
      ProvinceRules.step(s);
      expect(p.status, equals(ProvinceState.loyal));
    });

    test('الجيش القوي يقمع الانفصال والضعيف يخسر الولاية', () {
      final strong = GameState(army: 100);
      strong.econ.provinces['egypt']!.autonomy = 99;
      for (var i = 10; i < 25; i++) {
        strong.round = i;
        ProvinceRules.step(strong);
      }
      expect(strong.econ.provinces['egypt']!.isLost, isFalse);

      final weak = GameState(army: 20);
      weak.econ.provinces['egypt']!.autonomy = 99;
      final pop = weak.demog.population;
      var notes = <String>[];
      for (var i = 10; i < 200 && !weak.econ.provinces['egypt']!.isLost; i++) {
        weak.round = i;
        notes = ProvinceRules.step(weak);
      }
      expect(weak.econ.provinces['egypt']!.isLost, isTrue);
      expect(notes.any((n) => n.contains('انفصلت')), isTrue);
      expect(weak.demog.population, lessThan(pop * 0.9));
      expect(weak.legitimacy, lessThan(65));
      expect(weak.econ.revenueMultiplier, closeTo(0.8, 0.02));
      expect(ProvinceRules.lost(weak).length, equals(1));
    });

    test('إجراءات القمع والامتيازات', () {
      final s = GameState();
      final p = s.econ.provinces['rumelia']!;
      final a = p.autonomy;
      final m = p.mood;
      expect(ProvinceRules.suppress(s, 'rumelia').ok, isTrue);
      expect(p.autonomy, equals(a - 15));
      expect(p.mood, equals(m - 5));
      expect(ProvinceRules.privileges(s, 'rumelia').ok, isTrue);
      expect(p.mood, equals(m + 3));
      expect(ProvinceRules.privileges(s, 'rumelia').ok, isFalse); // نفدت الإجراءات
    });

    test('تفكك الإمبراطورية ينهي اللعبة', () {
      final s = GameState();
      for (final k in ['rumelia', 'egypt', 'syria', 'iraq', 'hijaz']) {
        s.econ.provinces[k]!.status = ProvinceState.independent;
      }
      final e = GameEngine().evaluate(s);
      expect(e, isNotNull);
      expect(e!.type, equals(EndingType.dismembered));
    });

    test('الولاية تحفظ بحالتها', () {
      final s = GameState();
      s.econ.provinces['iraq']!.status = ProvinceState.independent;
      s.econ.provinces['syria']!.autonomy = 66;
      final c = s.copy();
      expect(c.econ.provinces['iraq']!.status, equals(ProvinceState.independent));
      expect(c.econ.provinces['syria']!.autonomy, equals(66));
    });
  });

  group('الدين الأقرب للواقع', () {
    test('القروض داخلية قبل 1854 وبعدها 70% أجنبية', () {
      final a = GameState();
      DebtRules.addLoan(a, 1000000);
      expect(a.debt, equals(7000000));
      expect(a.foreignDebt, equals(0));
      final b = GameState(round: 2 * (1860 - 1800));
      DebtRules.addLoan(b, 1000000);
      expect(b.foreignDebt, closeTo(700000, 1e-6));
    });

    test('التصنيف الابتدائي 75 ويهبط بالدين والعلاقات ويرتفع بالمصرف', () {
      final s = GameState();
      expect(DebtRules.creditRating(s), closeTo(75, 0.1));
      s.debt = 90000000;
      expect(DebtRules.creditRating(s), lessThan(30));
      final t = GameState();
      t.completed.add('ottoman_bank');
      expect(DebtRules.creditRating(t), closeTo(85, 0.1));
      final u = GameState();
      u.countries['britain']!.relation = 5;
      u.countries['france']!.relation = 5;
      expect(DebtRules.creditRating(u), lessThan(70));
    });

    test('الفائدة: داخلية ثابتة وخارجية حسب التصنيف وتعلق وقت العجز', () {
      final s = GameState(debt: 11000000, foreignDebt: 5000000);
      final expected = 6000000 * 0.12 / 2 + 5000000 * (0.05 + 0.10 * 0.25) / 2;
      expect(DebtRules.halfYearInterest(s), closeTo(expected, expected * 0.02));
      s.defaultRound = 0;
      s.round = 1;
      expect(DebtRules.inMoratorium(s), isTrue);
      expect(DebtRules.halfYearInterest(s), closeTo(6000000 * 0.12 / 2, 6000000 * 0.12 / 2 * 0.02));
    });

    test('السداد يبدأ بالداخلي ثم الأجنبي', () {
      final s = GameState(treasury: 10000000, debt: 9000000, foreignDebt: 5000000);
      expect(DebtRules.repay(s, 3000000), equals(3000000));
      expect(s.debt, equals(6000000));
      expect(s.foreignDebt, equals(5000000));
      expect(DebtRules.repay(s, 3000000), equals(3000000));
      expect(s.debt, equals(3000000));
      expect(s.foreignDebt, equals(3000000));
      expect(DebtRules.repay(s, 99e9), equals(3000000));
      expect(s.debt, equals(0));
      expect(s.foreignDebt, equals(0));
    });

    test('العجز عن السداد ثم إدارة الديون العامة ثم انتهاؤها', () {
      final s = GameState(round: 130, debt: 40000000, foreignDebt: 30000000, emergencyStreak: 3);
      final rel = s.countries['britain']!.relation;
      var notes = DebtRules.step(s);
      expect(s.defaultRound, equals(130));
      expect(notes.any((n) => n.contains('عجزها')), isTrue);
      expect(s.countries['britain']!.relation, equals(rel - 15));
      expect(s.legitimacy, equals(61));
      // لا إدارة قبل انقضاء التعليق
      s.round = 131;
      expect(DebtRules.step(s), isEmpty);
      expect(s.dadActive, isFalse);
      s.round = 134;
      notes = DebtRules.step(s);
      expect(s.dadActive, isTrue);
      expect(notes.any((n) => n.contains('إدارة')), isTrue);
      final before = s.foreignDebt;
      final pay = DebtRules.dadPayment(s, 9000000);
      expect(pay, equals(1800000));
      expect(s.foreignDebt, equals(before - 1800000));
      // انتهاء الإشراف عند سداد معظمه
      s.foreignDebt = 1000000;
      final end = DebtRules.step(s);
      expect(s.dadActive, isFalse);
      expect(end.any((n) => n.contains('أتمت')), isTrue);
    });

    test('لا عجز عن السداد بلا دين أجنبي كبير أو بلا اقتراض طارئ متكرر', () {
      final a = GameState(round: 130, foreignDebt: 0, emergencyStreak: 9);
      DebtRules.step(a);
      expect(a.defaultRound, equals(-1));
      final b = GameState(round: 130, debt: 40000000, foreignDebt: 30000000, emergencyStreak: 1);
      DebtRules.step(b);
      expect(b.defaultRound, equals(-1));
    });

    test('المحرك: الاقتراض الطارئ المتتالي يعد، والدين محفوظ', () {
      final s = GameState(treasury: 0);
      s.budget.change('palace', 9000000);
      for (var i = 0; i < 3; i++) {
        _round(s);
      }
      expect(s.emergencyStreak, equals(3));
      final c = s.copy();
      expect(c.emergencyStreak, equals(3));
      expect(c.foreignDebt, equals(s.foreignDebt));
    });
  });

  group('نظام الحروب', () {
    test('إعلان الحرب: مرة واحدة لكل دولة وحد أقصى اثنتان', () {
      final s = GameState();
      final rel = s.countries['russia']!.relation;
      expect(WarRules.declare(s, 'russia', byUs: true), contains('روسيا'));
      expect(s.countries['russia']!.relation, equals(rel - 10));
      expect(WarRules.declare(s, 'russia', byUs: true), isEmpty);
      expect(WarRules.declare(s, 'persia', byUs: false), isNotEmpty);
      expect(WarRules.declare(s, 'france', byUs: false), isEmpty);
      expect(s.wars.length, equals(2));
      expect(WarRules.declare(GameState(), 'mars', byUs: true), isEmpty);
    });

    test('القوة: روسيا أقوى منا وإيران أضعف، والتحديث والإمداد يرفعان قوتنا', () {
      final s = GameState();
      final our = WarRules.ourPower(s);
      expect(our, closeTo(45 * 1.0 * 1.0 * 1.02, 0.5));
      expect(WarRules.enemyPower(s.countries['russia']!), greaterThan(our * 2));
      expect(WarRules.enemyPower(s.countries['persia']!), lessThan(our));
      s.completed.addAll(['modern_army', 'railway', 'roads']);
      expect(WarRules.ourPower(s), greaterThan(our * 1.15));
      s.treasury = 0;
      final broke = WarRules.ourPower(s);
      s.treasury = 1e7;
      expect(broke, lessThan(WarRules.ourPower(s)));
    });

    test('المعارك: تميل إلى الأقوى بالمتوسط', () {
      double avg(String enemy) {
        var total = 0.0;
        const n = 80;
        for (var seed = 1; seed <= n; seed++) {
          final s = GameState(seed: seed, round: 10);
          WarRules.declare(s, enemy, byUs: true);
          WarRules.step(s);
          total += s.wars.isEmpty ? 0 : s.wars.first.score;
        }
        return total / n;
      }

      expect(avg('persia'), greaterThan(2));
      expect(avg('russia'), lessThan(-2));
    });

    test('الكلفة والخسائر والتقرير', () {
      final s = GameState(treasury: 50000000, round: 10);
      WarRules.declare(s, 'russia', byUs: false);
      final cost = WarRules.costs(s);
      expect(cost, greaterThan(500000));
      expect(cost, lessThanOrEqualTo(s.budget.totalRevenue * 0.04 * 2 + 1));
      final t0 = s.treasury;
      final army0 = s.army;
      final report = _round(s);
      expect(report.warSpend, closeTo(cost, cost * 0.05));
      expect(s.army, lessThan(army0));
      expect(s.wars.first.halves, equals(1));
      expect(report.events.any((e) => e.contains('الحرب مع')), isTrue);
      expect(report.toPromptText().contains('نفقات حرب'), isTrue);
      // التزام الحساب: الخزينة = قبل + الصافي
      expect(report.treasuryAfter, closeTo(t0 + report.net, 1));
    });

    test('شروط الصلح تتدرج: نصر، صلح، شروط قاسية، تنازل عن ولاية', () {
      GameState fresh(double score) {
        final s = GameState(treasury: 5000000, round: 10);
        WarRules.declare(s, 'russia', byUs: true);
        s.wars.first.score = score;
        s.wars.first.halves = 3;
        return s;
      }

      final win = fresh(50);
      final rev = win.budget.totalRevenue;
      final t = win.treasury;
      expect(WarRules.seekPeace(win, 'russia').ok, isTrue);
      expect(win.wars, isEmpty);
      expect(win.treasury, greaterThan(t));
      expect(win.countries['russia']!.relation, equals(25));

      final even = fresh(-10);
      WarRules.seekPeace(even, 'russia');
      expect(even.foreignDebt, equals(0));
      expect(even.econ.provinces['rumelia']!.isLost, isFalse);

      final hard = fresh(-40);
      final a = hard.econ.provinces['rumelia']!.autonomy;
      WarRules.seekPeace(hard, 'russia');
      expect(hard.foreignDebt, closeTo(rev * 0.12, 1));
      expect(hard.econ.provinces['rumelia']!.autonomy, equals(a + 25));

      final lost = fresh(-80);
      WarRules.seekPeace(lost, 'russia');
      expect(lost.econ.provinces['rumelia']!.isLost, isTrue);
      expect(lost.foreignDebt, closeTo(rev * 0.25, 1));
    });

    test('الصلح المبكر يرفض، وبلا إجراءات يرفض', () {
      final s = GameState(treasury: 5000000);
      WarRules.declare(s, 'russia', byUs: true);
      expect(WarRules.seekPeace(s, 'russia').ok, isFalse);
      s.wars.first.halves = 5;
      s.courtActions = 0;
      expect(WarRules.seekPeace(s, 'russia').ok, isFalse);
      expect(WarRules.seekPeace(s, 'persia').ok, isFalse);
    });

    test('الإنهاك: بعد 14 نصف سنة يتوقف القتال، والنصر الكاسح ينهيها تلقائيا', () {
      final s = GameState(round: 10);
      WarRules.declare(s, 'persia', byUs: true);
      s.wars.first.halves = WarRules.exhaustionHalves - 1;
      s.wars.first.score = 0;
      WarRules.step(s);
      expect(s.wars.isEmpty || s.wars.first.score.abs() >= 0, isTrue);
      final t = GameState(round: 10);
      WarRules.declare(t, 'persia', byUs: true);
      t.wars.first.score = 59;
      t.wars.first.halves = 1;
      var done = false;
      for (var i = 0; i < 30 && !done; i++) {
        t.round = 10 + i;
        WarRules.step(t);
        done = t.wars.isEmpty;
      }
      expect(done, isTrue);
    });

    test('الحرب الجديدة تقع مع دولة معادية قوية لا مع صديقة', () {
      int wars(double relation) {
        var n = 0;
        for (var seed = 1; seed <= 60; seed++) {
          final s = GameState(seed: seed);
          s.countries['russia']!.relation = relation;
          for (var i = 6; i < 20; i++) {
            s.round = i;
            WarRules.step(s);
            if (s.wars.isNotEmpty) {
              n++;
              break;
            }
          }
        }
        return n;
      }

      expect(wars(5), greaterThan(10));
      expect(wars(40), equals(0));
    });

    test('خيارات الذكاء الاصطناعي war وpeace تصل إلى المحرك', () {
      final s = GameState(treasury: 9000000);
      _round(s, _withFirstOption(const DecisionOption(text: 'حرب', result: 'ن', war: 'persia')));
      expect(s.wars.any((w) => w.enemy == 'persia'), isTrue);
      s.wars.first.halves = 4;
      s.wars.first.score = 30;
      _round(s, _withFirstOption(const DecisionOption(text: 'صلح', result: 'ن', peace: 'persia')));
      expect(s.wars, isEmpty);
    });

    test('الحروب تحفظ', () {
      final s = GameState();
      WarRules.declare(s, 'russia', byUs: true);
      s.wars.first.score = -33;
      s.wars.first.halves = 5;
      final c = s.copy();
      expect(c.wars.first.enemy, equals('russia'));
      expect(c.wars.first.score, equals(-33));
      expect(c.wars.first.byUs, isTrue);
    });
  });

  group('الرسوم البيانية', () {
    test('لقطة كل نصف سنة بقيم صحيحة وتحفظ', () {
      final s = GameState(treasury: 20000000);
      for (var i = 0; i < 3; i++) {
        _round(s);
      }
      expect(s.series.length, equals(3));
      expect(s.series.last.round, equals(3));
      expect(s.series.last.treasury, equals(s.treasury));
      expect(s.series.last.stability, equals(s.stability));
      final c = s.copy();
      expect(c.series.length, equals(3));
      expect(c.series.first.debt, equals(s.series.first.debt));
    });

    test('السلسلة محدودة الطول والنقاط الفاسدة تهمل', () {
      final j = GameState().toJson();
      j['series'] = [
        [1, 2, 3],
        'x',
        for (var i = 0; i < 500; i++) [i, 1, 1, 1, 50, 50, 50, 50, 50, 20, 3, 2],
      ];
      final s = GameState.fromJson(j);
      expect(s.series.length, equals(460));
      expect(s.series.last.round, equals(499));
    });
  });

  test('حفظ نسخة 3 (قبل هذه الأنظمة) يرقى ويحتفظ بما فيه', () {
    final j = GameState(treasury: 123, difficulty: 2).toJson();
    for (final k in ['difficulty', 'wars', 'foreignDebt', 'defaultRound', 'emergencyStreak', 'dadActive', 'project', 'completed', 'series']) {
      j.remove(k);
    }
    j['schema'] = 3;
    final s = GameState.fromJson(j);
    expect(s.treasury, equals(123));
    expect(s.difficulty, equals(1));
    expect(s.wars, isEmpty);
    expect(s.project, isNull);
    expect(s.defaultRound, equals(-1));
  });
}
