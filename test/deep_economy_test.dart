import 'package:flutter_test/flutter_test.dart';
import 'package:ottoman_empire_1800/models/game_state.dart';
import 'package:ottoman_empire_1800/models/systems.dart';
import 'package:ottoman_empire_1800/services/deep_economy.dart';
import 'package:ottoman_empire_1800/services/economy.dart';
import 'package:ottoman_empire_1800/services/sim_common.dart';
import 'package:ottoman_empire_1800/services/spies_climate.dart';
import 'package:ottoman_empire_1800/services/stability.dart';

void main() {
  group('المناخ', () {
    test('لا أحداث في أول سنتين والمحصول عادي', () {
      final s = GameState();
      for (var i = 0; i < graceRounds; i++) {
        s.round = i;
        expect(ClimateRules.step(s), isEmpty);
        expect(s.econ.provinces.values.every((p) => p.harvest == 1.0), isTrue);
      }
    });

    test('الأحداث تقع بنسبة معقولة وحتمية بالبذرة', () {
      List<String> run(int seed) {
        final s = GameState(seed: seed);
        final out = <String>[];
        for (var i = 4; i < 604; i++) {
          s.round = i;
          out.addAll(ClimateRules.step(s));
        }
        return out;
      }

      final a = run(5);
      final b = run(5);
      expect(a, equals(b));
      expect(a.length, inInclusiveRange(120, 240));
      expect(a.any((e) => e.contains('جفاف')), isTrue);
      expect(a.any((e) => e.contains('طاعون')), isTrue);
      expect(a.any((e) => e.contains('وفير')), isTrue);
    });

    test('الجفاف ينقص مضاعف الإيراد ويرفع الحبوب، والسعر يعود للمعتاد', () {
      final s = GameState();
      var found = false;
      for (var i = 4; i < 400 && !found; i++) {
        s.round = i;
        final notes = ClimateRules.step(s);
        if (notes.any((n) => n.contains('جفاف'))) {
          found = true;
          expect(s.econ.revenueMultiplier, lessThan(1.0));
          expect(s.econ.grain, greaterThan(110));
        }
      }
      expect(found, isTrue);
      final calm = GameState();
      calm.econ.grain = 220;
      calm.round = 0;
      ClimateRules.step(calm);
      expect(calm.econ.grain, lessThan(220));
    });
  });

  group('الاقتصاد العميق', () {
    test('تغيير الضرائب يغير مزاج الولايات، والتخفيف يرضيها أقل من أثر الرفع', () {
      final s = GameState();
      final before = s.econ.provinces['anatolia']!.mood;
      DeepEconomyRules.onLineChange(s, 'land', 1800000);
      expect(s.econ.provinces['anatolia']!.mood, closeTo(before - 6, 1e-9));
      DeepEconomyRules.onLineChange(s, 'land', -1800000);
      expect(s.econ.provinces['anatolia']!.mood, closeTo(before - 3, 1e-9));
      DeepEconomyRules.onLineChange(s, 'army', 5000000);
      expect(s.econ.provinces['anatolia']!.mood, closeTo(before - 3, 1e-9));
    });

    test('رفع بند الإدارة يخفض الفساد', () {
      final s = GameState();
      DeepEconomyRules.onLineChange(s, 'admin', 1800000);
      expect(s.econ.corruption, lessThan(45));
    });

    test('العجز المتواصل يغذي التضخم والفائض يبرده، ومنه تنمو الميزانية', () {
      final s = GameState();
      for (var i = 0; i < 8; i++) {
        DeepEconomyRules.step(s, net: -1e6);
      }
      expect(s.econ.deficitStreak, equals(8));
      expect(s.econ.inflation, greaterThan(3.5));
      final high = s.econ.inflation;
      for (var i = 0; i < 4; i++) {
        DeepEconomyRules.step(s, net: 1e6);
      }
      expect(s.econ.deficitStreak, equals(0));
      expect(s.econ.surplusStreak, equals(4));
      expect(s.econ.inflation, lessThan(high));
      final t = GameState();
      final rev = t.budget.totalRevenue;
      DeepEconomyRules.applyNominalGrowth(t);
      expect(t.budget.totalRevenue, closeTo(rev * 1.01, 1));
      expect(t.econ.priceIndex, closeTo(1.01, 1e-12));
    });

    test('الفائدة ترتفع مع التضخم الشديد فقط', () {
      expect(EconomyRules.halfYearInterest(10e6), closeTo(600000, 1));
      expect(EconomyRules.halfYearInterest(10e6, inflation: 10), greaterThan(EconomyRules.halfYearInterest(10e6)));
    });

    test('السكان والمدارس والقراءة تنمو ببطء بالإنفاق المدني', () {
      final s = GameState();
      final d = s.demog;
      final pop = d.population;
      final schools = d.schools;
      final lit = d.literacy;
      DeepEconomyRules.step(s, net: 0);
      expect(d.population, greaterThan(pop));
      expect(d.schools - schools, closeTo(1000000 / 2 * 0.30 / 1600, 0.5));
      expect(d.literacy, greaterThan(lit));
      expect(d.literacy - lit, lessThan(0.2));
    });

    test('الكساد والمجاعة يخفضان السكان ونسبة التعلم لا تنهار', () {
      final s = GameState();
      s.econ.grain = 250;
      final pop = s.demog.population;
      for (var i = 0; i < 10; i++) {
        s.econ.grain = 250;
        DeepEconomyRules.step(s, net: 0);
      }
      expect(s.demog.population, lessThan(pop * 1.01));
      expect(s.demog.literacy, greaterThan(1));
    });

    test('مزاج الولايات يعود إلى أصله تدريجيا', () {
      final s = GameState();
      s.econ.provinces['rumelia']!.mood = 10;
      for (var i = 0; i < 60; i++) {
        DeepEconomyRules.step(s, net: 0);
      }
      expect(s.econ.provinces['rumelia']!.mood, greaterThan(30));
    });
  });

  group('قواعد الاستقرار', () {
    test('لا انجراف في الظروف الابتدائية', () {
      final s = GameState();
      final before = StabilityState.keys.map((k) => s.stab[k]).toList();
      StabilityRules.step(s, debtRatio: 0.33, emergency: false);
      expect(StabilityState.keys.map((k) => s.stab[k]).toList(), equals(before));
    });

    test('المجاعة والدين الثقيل والاستياء الإقليمي تضرب أبعادها', () {
      final s = GameState();
      s.econ.grain = 200;
      for (final p in s.econ.provinces.values) {
        p.mood = 15;
      }
      s.econ.deficitStreak = 9;
      StabilityRules.step(s, debtRatio: 4, emergency: true);
      expect(s.stab['social'], lessThan(55));
      expect(s.stab['regional'], lessThan(45));
      expect(s.stab['economic'], lessThan(50));
    });

    test('الازدهار يرفع الأبعاد المقابلة', () {
      final s = GameState(legitimacy: 90);
      s.econ.surplusStreak = 5;
      for (final p in s.econ.provinces.values) {
        p.mood = 80;
      }
      StabilityRules.step(s, debtRatio: 0.5, emergency: false);
      expect(s.stab['political'], greaterThan(60));
      expect(s.stab['economic'], greaterThan(50));
      expect(s.stab['regional'], greaterThan(45));
    });
  });
}
