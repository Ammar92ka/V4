import 'package:flutter_test/flutter_test.dart';
import 'package:ottoman_empire_1800/engine/calibrator.dart';
import 'package:ottoman_empire_1800/engine/game_engine.dart';
import 'package:ottoman_empire_1800/models/game_state.dart';
import 'package:ottoman_empire_1800/models/round_plan.dart';
import 'package:ottoman_empire_1800/models/systems.dart';
import 'package:ottoman_empire_1800/services/diplomacy.dart';
import 'package:ottoman_empire_1800/services/powers.dart';
import 'package:ottoman_empire_1800/services/sim_common.dart';
import 'package:ottoman_empire_1800/services/spies_climate.dart';

import 'support/bots.dart';

void main() {
  group('إجراءات القوى', () {
    test('الترضية: تكلف وترفع الرضا وتستهلك إجراء', () {
      final s = GameState();
      final before = s.powers['janissaries']!.satisfaction;
      final t = s.treasury;
      final r = PowerRules.appease(s, 'janissaries');
      expect(r.ok, isTrue);
      expect(s.powers['janissaries']!.satisfaction, equals(before + 8));
      expect(s.treasury, equals(t - costShare(GameState(), PowerRules.appeaseShare)));
      expect(s.courtActions, equals(1));
      expect(s.courtLog.length, equals(1));
    });

    test('بلا إجراءات أو بلا مال يرفض ولا يتغير شيء', () {
      final s = GameState(courtActions: 0);
      final t = s.treasury;
      expect(PowerRules.appease(s, 'ulema').ok, isFalse);
      expect(s.treasury, equals(t));
      final poor = GameState(treasury: 10);
      expect(PowerRules.startProject(poor, 'ulema', 'reform').ok, isFalse);
      expect(poor.projects, isEmpty);
      expect(poor.courtActions, equals(2));
      expect(PowerRules.appease(GameState(), 'ghost').ok, isFalse);
    });

    test('المشروع الطويل يعمل كل نصف سنة وينتهي، ومشروع واحد لكل قوة', () {
      final s = GameState();
      expect(PowerRules.startProject(s, 'ulema', 'reform').ok, isTrue);
      expect(PowerRules.startProject(s, 'ulema', 'contain').ok, isFalse);
      final infl = s.powers['ulema']!.influence;
      final engine = GameEngine();
      s.plan = Calibrator.calibrate(neutralPlan(), s);
      s.picks = [0, 0, 0];
      engine.resolveRound(s);
      expect(s.powers['ulema']!.influence, closeTo(infl - 1.5, 1e-9));
      expect(s.projects.first.remaining, equals(5));
      for (var i = 0; i < 5; i++) {
        s.plan = Calibrator.calibrate(neutralPlan(), s);
        s.picks = [0, 0, 0];
        engine.resolveRound(s);
      }
      expect(s.projects, isEmpty);
    });

    test('حل قوة منخفضة الخطر ينجح نهائيا', () {
      final s = GameState();
      final r = PowerRules.dissolve(s, 'merchants');
      expect(r.ok, isTrue);
      expect(s.powers['merchants']!.dissolved, isTrue);
      expect(s.powers['merchants']!.danger, equals(0));
      expect(PowerRules.appease(s, 'merchants').ok, isFalse);
    });

    test('حل قوة شديدة الخطر حتمي بالبذرة: يرتد أو ينجح بنفس النتيجة دائما', () {
      final a = GameState();
      final b = GameState();
      final ra = PowerRules.dissolve(a, 'janissaries');
      final rb = PowerRules.dissolve(b, 'janissaries');
      expect(ra.ok, equals(rb.ok));
      expect(a.legitimacy, equals(b.legitimacy));
      if (ra.ok) {
        expect(a.powers['janissaries']!.dissolved, isTrue);
      } else {
        expect(a.legitimacy, equals(59));
        expect(a.powers['janissaries']!.dissolved, isFalse);
      }
    });

    test('خيار ذكاء اصطناعي يحل قوة فتنعكس الحالة والأحداث', () {
      final s = GameState();
      final plan = neutralPlan();
      final withDissolve = RoundPlan(
        headline: 'h',
        briefing: 'b',
        decisions: [
          Decision(
            category: DecisionCategory.internal,
            title: 't',
            scene: 's',
            dilemma: 'd',
            options: const [
              DecisionOption(text: 'حل التجار', result: 'ن', dissolve: 'merchants'),
              DecisionOption(text: 'ب', result: 'ن'),
              DecisionOption(text: 'ج', result: 'ن'),
            ],
          ),
          plan.decisions[1],
          plan.decisions[2],
        ],
      );
      s.plan = Calibrator.calibrate(withDissolve, s);
      s.picks = [0, 0, 0];
      final report = GameEngine().resolveRound(s);
      expect(s.powers['merchants']!.dissolved, isTrue);
      expect(report.events.any((e) => e.contains('التجار')), isTrue);
    });

    test('المؤامرة: تنفجر أو تكشف، والاستخبارات الداخلية تكشف أكثر', () {
      int run(int level) {
        final s = GameState(domesticSpy: level);
        s.powers['janissaries']!.influence = 100;
        s.powers['janissaries']!.satisfaction = 0;
        var detected = 0;
        for (var i = 0; i < 300; i++) {
          s.round = 10 + i;
          final notes = PowerRules.step(s, emergency: false);
          detected += notes.where((n) => n.contains('كشفت')).length;
          s.legitimacy = 65;
        }
        return detected;
      }

      expect(run(0), equals(0));
      expect(run(2), greaterThan(0));
    });

    test('لا مؤامرات في أول سنتين', () {
      final s = GameState();
      s.powers['janissaries']!.influence = 100;
      s.powers['janissaries']!.satisfaction = 0;
      for (var i = 0; i < graceRounds; i++) {
        s.round = i;
        final notes = PowerRules.step(s, emergency: false);
        expect(notes.where((n) => n.contains('تمرد') || n.contains('مؤامرة')), isEmpty);
      }
    });
  });

  group('الدبلوماسية والسفارات', () {
    test('افتتاح السفارة وإغلاقها يغيران بند الإدارة والعلاقة', () {
      final s = GameState();
      final admin = s.budget.lineValue('admin');
      final t = s.treasury;
      final r = DiplomacyRules.openEmbassy(s, 'russia');
      expect(r.ok, isTrue);
      expect(s.countries['russia']!.embassy, isTrue);
      expect(s.budget.lineValue('admin'), equals(admin + 180000));
      expect(s.treasury, equals(t - 360000));
      expect(DiplomacyRules.openEmbassy(s, 'russia').ok, isFalse);
      final rel = s.countries['russia']!.relation;
      expect(DiplomacyRules.closeEmbassy(s, 'russia').ok, isTrue);
      expect(s.budget.lineValue('admin'), equals(admin));
      expect(s.countries['russia']!.relation, equals(rel - 4));
    });

    test('معامل الاقتراض 1.0 عند البدء ويتبع علاقات الدائنين', () {
      final s = GameState();
      expect(DiplomacyRules.creditFactor(s), closeTo(1.0, 1e-9));
      for (final k in ['britain', 'france', 'austria']) {
        s.countries[k]!.relation = 10;
      }
      expect(DiplomacyRules.creditFactor(s), lessThan(0.7));
      for (final k in ['britain', 'france', 'austria']) {
        s.countries[k]!.relation = 95;
      }
      expect(DiplomacyRules.creditFactor(s), greaterThan(1.1));
      // يضيق سقف القرض في المعايرة
      final rev = s.budget.totalRevenue;
      const o = DecisionOption(text: 'قرض', result: 'ن', loan: 1e12);
      final high = Calibrator.calibrateOption(o, rev, creditFactor: DiplomacyRules.creditFactor(s));
      final low = Calibrator.calibrateOption(o, rev, creditFactor: 0.6);
      expect(low.loan, lessThan(high.loan));
    });

    test('الهدايا ترفع العلاقة وتستهلك إجراء', () {
      final s = GameState();
      final rel = s.countries['persia']!.relation;
      expect(DiplomacyRules.gift(s, 'persia').ok, isTrue);
      expect(s.countries['persia']!.relation, equals(rel + 6));
      expect(s.courtActions, equals(1));
    });

    test('المعاهدة التجارية: تزيد العلاقة وتخفض المنافس وتؤجل مكسب الجمارك وتبرد', () {
      final s = GameState();
      final customs = s.budget.lineValue('customs');
      expect(DiplomacyRules.tradeTreaty(s, 'britain').ok, isTrue);
      expect(s.countries['britain']!.relation, equals(70));
      expect(s.countries['france']!.relation, equals(25));
      expect(s.pending.length, equals(1));
      expect(DiplomacyRules.tradeTreaty(s, 'britain').ok, isFalse);
      // فرنسا علاقتها أقل من 40
      expect(DiplomacyRules.tradeTreaty(s, 'france').ok, isFalse);
      // بعد سنة يظهر مكسب الجمارك
      final engine = GameEngine();
      for (var i = 0; i < 2; i++) {
        s.plan = Calibrator.calibrate(neutralPlan(), s);
        s.picks = [0, 0, 0];
        engine.resolveRound(s);
      }
      expect(s.budget.lineValue('customs'), greaterThan(customs * 1.0201 + 200000));
    });

    test('أثر الخيارات على العلاقات وتحسن العلاقة بالسفارة وتدهورها بدونها', () {
      final s = GameState();
      DiplomacyRules.applyRelations(s, {'russia': -8, 'persia': 5, 'nowhere': 3});
      expect(s.countries['russia']!.relation, equals(42));
      expect(s.countries['persia']!.relation, equals(50));
      final a = GameState();
      a.countries['britain']!.relation = 50;
      DiplomacyRules.step(a);
      expect(a.countries['britain']!.relation, greaterThan(50));
      final b = GameState();
      b.countries['france']!.relation = 90;
      DiplomacyRules.step(b);
      expect(b.countries['france']!.relation, lessThan(90));
    });

    test('جيش ضعيف يضعف علاقتنا بروسيا والنمسا', () {
      final s = GameState(army: 10);
      final ru = s.countries['russia']!.relation;
      DiplomacyRules.step(s);
      expect(s.countries['russia']!.relation, lessThan(ru));
    });
  });

  group('الاستخبارات', () {
    test('مستوى الشبكة: تجنيد مرة وتشغيل في بند الإدارة', () {
      final s = GameState();
      final admin = s.budget.lineValue('admin');
      final t = s.treasury;
      expect(DiplomacyRules.setSpyLevel(s, 'russia', 2).ok, isTrue);
      expect(s.treasury, equals(t - 360000));
      expect(s.budget.lineValue('admin'), equals(admin + 540000));
      expect(DiplomacyRules.setSpyLevel(s, 'russia', 0).ok, isTrue);
      expect(s.budget.lineValue('admin'), equals(admin));
      expect(DiplomacyRules.setDomesticSpy(GameState(treasury: 1), 1).ok, isFalse);
    });

    test('تقارير لمن لنا فيه سفارة أو شبكة فقط، وتنكشف حقيقتها بعد نصف سنة', () {
      final s = GameState();
      s.countries['russia']!.spy = 2;
      final targets = <String>{};
      final notes = <String>[];
      for (var i = 0; i < 80; i++) {
        s.round = i;
        notes.addAll(SpyRules.step(s));
        targets.addAll(s.intel.map((r) => r.target));
      }
      expect(targets.contains('russia'), isTrue);
      expect(targets.contains('persia'), isFalse);
      expect(notes.any((n) => n.contains('تبين')), isTrue);
      expect(s.intel.length, lessThanOrEqualTo(SpyRules.maxKept));
      expect(s.intel.first.revealed, isTrue);
    });

    test('دقة التقارير تتبع الجودة', () {
      double accuracy(int spy, bool embassy) {
        final s = GameState();
        final c = s.countries['russia']!;
        c.spy = spy;
        c.embassy = embassy;
        c.relation = 50;
        for (final k in ['britain', 'austria', 'france', 'persia']) {
          s.countries[k]!.embassy = false;
          s.countries[k]!.spy = 0;
        }
        var total = 0;
        var good = 0;
        for (var i = 0; i < 600; i++) {
          s.round = i;
          s.intel.clear();
          SpyRules.step(s);
          for (final r in s.intel.where((r) => r.round == i)) {
            total++;
            if (r.truth) good++;
          }
        }
        return total == 0 ? 0 : good / total;
      }

      final high = accuracy(2, true);
      final low = accuracy(1, false);
      expect(high, greaterThan(0.80));
      expect(low, lessThan(0.70));
      expect(high, greaterThan(low));
    });

    test('تقرير الجولة لا يكشف الحقيقة للذكاء الاصطناعي قبل نصف سنة', () {
      final s = GameState();
      s.plan = Calibrator.calibrate(neutralPlan(), s);
      s.picks = [0, 0, 0];
      final report = GameEngine().resolveRound(s);
      expect(report.events.any((e) => e.contains('موثوقية')), isTrue);
      expect(s.lastReport.contains('تبين'), isFalse);
    });
  });

  group('السداد من المحرك', () {
    test('يسدد من الدين من الخزينة ويصفر الطلب ويظهر في التقرير', () {
      final s = GameState(treasury: 10000000, debt: 6000000, repay: 4000000);
      s.plan = Calibrator.calibrate(neutralPlan(), s);
      s.picks = [0, 0, 0];
      final report = GameEngine().resolveRound(s);
      expect(report.repaid, equals(4000000));
      expect(s.debt, closeTo(2000000, 1));
      expect(s.repay, equals(0));
      expect(report.toPromptText().contains('سداد دين'), isTrue);
    });

    test('لا يسدد أكثر من الدين ولا من الخزينة', () {
      final s = GameState(treasury: 3000000, debt: 1000000, repay: 9e9);
      s.plan = Calibrator.calibrate(neutralPlan(), s);
      s.picks = [0, 0, 0];
      final report = GameEngine().resolveRound(s);
      expect(report.repaid, equals(1000000));
      expect(s.debt, closeTo(0, 1));
      expect(s.treasury, greaterThan(0));
    });
  });

  group('قرارات الذكاء الاصطناعي تصل إلى الأنظمة', () {
    test('rel وpow تغير العلاقات ورضا القوى فوريا', () {
      final s = GameState();
      final plan = RoundPlan(
        headline: 'h',
        briefing: 'b',
        decisions: [
          Decision(
            category: DecisionCategory.foreign,
            title: 't',
            scene: 's',
            dilemma: 'd',
            options: const [
              DecisionOption(text: 'أ', result: 'ن', relations: {'britain': 5}, powerMood: {'ulema': -7}),
              DecisionOption(text: 'ب', result: 'ن'),
              DecisionOption(text: 'ج', result: 'ن'),
            ],
          ),
          neutralPlan().decisions[1],
          neutralPlan().decisions[2],
        ],
      );
      s.plan = Calibrator.calibrate(plan, s);
      s.picks = [0, 0, 0];
      final ulema = s.powers['ulema']!.satisfaction;
      GameEngine().resolveRound(s);
      // العلاقة تتحسن بالسفارة أيضا (+0.3)
      expect(s.countries['britain']!.relation, greaterThanOrEqualTo(67));
      expect(s.powers['ulema']!.satisfaction, lessThan(ulema - 5));
    });

    test('المعايرة تقص ما يزيد عن الحد وتحدد عدد المفاتيح', () {
      const o = DecisionOption(
        text: 'x',
        result: 'y',
        relations: {'britain': 50, 'france': -50, 'russia': 3, 'persia': 4},
        powerMood: {'ulema': 99},
      );
      final c = Calibrator.calibrateOption(o, 1e7);
      expect(c.relations.length, equals(Calibrator.maxMapKeys));
      expect(c.relations['britain'], equals(Calibrator.maxRelation));
      expect(c.relations['france'], equals(-Calibrator.maxRelation));
      expect(c.powerMood['ulema'], equals(Calibrator.maxPowerMood));
      expect(c.calibrated, isTrue);
    });
  });
}
