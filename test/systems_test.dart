import 'package:flutter_test/flutter_test.dart';
import 'package:ottoman_empire_1800/models/budget.dart';
import 'package:ottoman_empire_1800/models/game_state.dart';
import 'package:ottoman_empire_1800/models/systems.dart';

void main() {
  group('الاستقرار', () {
    test('المتوسط يطابق الرقم الكلي عند كل القيم بما فيها الحدود', () {
      for (final t in [0, 3, 5, 12, 30, 55, 90, 95, 100]) {
        expect(StabilityState.fromTotal(t).total, closeTo(t.toDouble(), 0.001));
      }
    });

    test('البدء الافتراضي ستة أبعاد متوسطها 55', () {
      final s = GameState();
      expect(s.stability, equals(55));
      expect(StabilityState.keys.map((k) => s.stab[k].round()).toList(), equals([50, 55, 55, 60, 65, 45]));
    });

    test('shiftAll يلتزم بالحدود، وcountBelow يعد الأبعاد المنهارة', () {
      final st = StabilityState.fromTotal(55);
      st.shiftAll(500);
      expect(st.total, equals(100));
      st.shiftAll(-1000);
      expect(st.total, equals(0));
      expect(st.countBelow(8), equals(6));
      st.shift('social', 50);
      expect(st.countBelow(8), equals(5));
    });

    test('ضبط الاستقرار الكلي يزيح الأبعاد معا', () {
      final s = GameState();
      s.stability = 30;
      expect(s.stability, equals(30));
      expect(s.stab['regional'], lessThan(s.stab['religious']));
    });
  });

  group('قوى الدولة', () {
    test('الانكشارية أخطر القوى عند البدء، والمحلولة خطرها صفر', () {
      final s = GameState();
      final jan = s.powers['janissaries']!;
      for (final p in s.powers.values) {
        expect(p.danger, inInclusiveRange(0, 100));
        if (p.key != 'janissaries') expect(p.danger, lessThan(jan.danger));
      }
      jan.dissolved = true;
      expect(jan.danger, equals(0));
    });

    test('ثمان قوى بمفاتيح معروفة', () {
      expect(powerDefs.length, equals(8));
      expect(isPowerKey('ulema'), isTrue);
      expect(isPowerKey('nobody'), isFalse);
    });
  });

  group('مضاعف الإيراد', () {
    test('يساوي 1.0 تماما في بداية الحملة', () {
      expect(EconomyState().revenueMultiplier, equals(1.0));
    });

    test('الجفاف والفساد وغضب الولايات تنقصه، والوفرة والرضا تزيده', () {
      final e = EconomyState();
      e.provinces['anatolia']!.harvest = 0.65;
      expect(e.revenueMultiplier, lessThan(1.0));
      final good = EconomyState();
      for (final p in good.provinces.values) {
        p.harvest = 1.1;
      }
      expect(good.revenueMultiplier, greaterThan(1.0));
      final corrupt = EconomyState(corruption: 80);
      expect(corrupt.revenueMultiplier, lessThan(1.0));
      final clean = EconomyState(corruption: 20);
      expect(clean.revenueMultiplier, greaterThan(1.0));
      final angry = EconomyState();
      for (final p in angry.provinces.values) {
        p.mood = 10;
      }
      expect(angry.revenueMultiplier, lessThan(1.0));
    });

    test('التضخم الابتدائي يعطي نموا اسميا 1% لنصف السنة', () {
      expect(EconomyState().nominalGrowth, closeTo(0.01, 1e-12));
    });
  });

  group('الحفظ', () {
    test('كل الأنظمة الجديدة تحفظ وتستعاد', () {
      final s = GameState(seed: 77, courtActions: 1, repay: 123456, domesticSpy: 2);
      s.stab.shift('regional', -20);
      s.powers['ulema']!.satisfaction = 12;
      s.powers['mamluks']!.dissolved = true;
      s.projects.add(PowerProject('tribes', 'contain', 4));
      s.countries['russia']!.embassy = true;
      s.countries['russia']!.spy = 2;
      s.countries['russia']!.relation = 33;
      s.intel.add(SpyReport(round: 3, target: 'russia', claim: 'ادعاء', reliability: 75, truth: true));
      s.econ.grain = 180;
      s.econ.corruption = 61;
      s.econ.provinces['egypt']!.mood = 12;
      s.demog.literacy = 7.5;
      s.world = WorldMemory(wars: ['حرب مع روسيا']);
      s.courtLog.add('ترضية');
      s.events.add('جفاف');
      final copy = s.copy();
      expect(copy.stab['regional'], closeTo(s.stab['regional'], 1e-9));
      expect(copy.powers['ulema']!.satisfaction, equals(12));
      expect(copy.powers['mamluks']!.dissolved, isTrue);
      expect(copy.projects.length, equals(1));
      expect(copy.projects.first.remaining, equals(4));
      expect(copy.countries['russia']!.embassy, isTrue);
      expect(copy.countries['russia']!.spy, equals(2));
      expect(copy.intel.first.claim, equals('ادعاء'));
      expect(copy.econ.grain, equals(180));
      expect(copy.econ.provinces['egypt']!.mood, equals(12));
      expect(copy.demog.literacy, equals(7.5));
      expect(copy.world.wars, equals(['حرب مع روسيا']));
      expect(copy.courtActions, equals(1));
      expect(copy.repay, equals(123456));
      expect(copy.domesticSpy, equals(2));
      expect(copy.seed, equals(77));
      expect(copy.courtLog, equals(['ترضية']));
      expect(copy.events, equals(['جفاف']));
    });

    test('حفظ قديم (نسخة 2 بلا أنظمة) يرقى تلقائيا ويحتفظ بما فيه', () {
      final old = GameState(treasury: 777, debt: 888, legitimacy: 40, stability: 33, army: 22).toJson();
      for (final k in [
        'stab', 'powers', 'projects', 'econ', 'countries', 'domesticSpy', 'intel', 'demog',
        'world', 'courtActions', 'repay', 'courtLog', 'events', 'seed',
      ]) {
        old.remove(k);
      }
      old['schema'] = 2;
      final s = GameState.fromJson(old);
      expect(s.treasury, equals(777));
      expect(s.legitimacy, equals(40));
      expect(s.stability, equals(33));
      expect(s.powers.length, equals(8));
      expect(s.countries.length, equals(6));
      expect(s.courtActions, equals(2));
      expect(s.econ.revenueMultiplier, equals(1.0));
    });

    test('صيغة غير مدعومة ترفض', () {
      final j = GameState().toJson();
      j['schema'] = 1;
      expect(() => GameState.fromJson(j), throwsA(isA<FormatException>()));
    });

    test('قيم فاسدة في الأنظمة تقص ولا تكسر', () {
      final j = GameState().toJson();
      j['econ'] = {'grain': 'x', 'inflation': 9999, 'corruption': -5, 'provinces': 'bad'};
      j['powers'] = [
        {'key': 'ulema', 'influence': 500, 'satisfaction': -3},
        {'key': 'ghost'},
        7,
      ];
      j['countries'] = [
        {'key': 'france', 'relation': 'abc', 'spy': 9},
      ];
      final s = GameState.fromJson(j);
      expect(s.econ.inflation, equals(40));
      expect(s.econ.corruption, equals(0));
      expect(s.powers['ulema']!.influence, equals(100));
      expect(s.powers['ulema']!.satisfaction, equals(0));
      expect(s.countries['france']!.spy, equals(2));
    });
  });

  group('ذاكرة العالم', () {
    test('تقص العناصر والأطوال وتتجاهل غير النصوص', () {
      final w = WorldMemory.fromJson({
        'wars': [for (var i = 0; i < 10; i++) 'حرب $i', 5, null, '  '],
        'alliances': ['x' * 300],
        'reforms': 'ليست قائمة',
      });
      expect(w.wars.length, equals(WorldMemory.maxItems));
      expect(w.alliances.first.length, lessThanOrEqualTo(WorldMemory.maxLen));
      expect(w.reforms, isEmpty);
      expect(WorldMemory().isEmpty, isTrue);
    });
  });

  test('الميزانية الابتدائية لم تتغير', () {
    final b = Budget.initial1800();
    expect(b.totalRevenue, equals(18000000));
    expect(b.totalSpending, equals(17000000));
  });
}
