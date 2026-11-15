import 'package:flutter_test/flutter_test.dart';
import 'package:ottoman_empire_1800/models/game_state.dart';
import 'package:ottoman_empire_1800/models/systems.dart';

import 'support/bots.dart';

/// اختبارات توازن بلاعبين آليين. ليست إثباتا أن اللعبة عادلة، لكنها تمنع
/// أي تعديل في الأرقام من أن يجعل الحملة مستحيلة أو أن يكسر الثوابت.
void _invariants(GameState s) {
  expect(s.treasury.isFinite && s.treasury >= 0, isTrue);
  expect(s.debt.isFinite && s.debt >= 0, isTrue);
  for (final v in [s.legitimacy, s.army, s.foreign, s.education, s.stability]) {
    expect(v, inInclusiveRange(0, 100));
  }
  for (final k in StabilityState.keys) {
    expect(s.stab[k], inInclusiveRange(0, 100));
  }
  for (final p in s.powers.values) {
    expect(p.influence, inInclusiveRange(0, 100));
    expect(p.satisfaction, inInclusiveRange(0, 100));
  }
  for (final c in s.countries.values) {
    expect(c.relation, inInclusiveRange(0, 100));
  }
  expect(s.econ.inflation, inInclusiveRange(1, 12));
  expect(s.econ.revenueMultiplier.isFinite, isTrue);
  expect(s.demog.population.isFinite && s.demog.population > 0, isTrue);
  expect(s.budget.totalRevenue.isFinite, isTrue);
}

void main() {
  test('لاعب لا يفعل شيئا يصمد أكثر من 12 سنة قبل أن يضغط العجز', () {
    final run = playBot(GameState(), prudent: false, check: _invariants);
    expect(run.rounds, greaterThanOrEqualTo(24));
    expect(run.ending, isNotNull);
  });

  test('لاعب حذر يصمد معظم الحملة في أغلب البذور', () {
    var long = 0;
    const seeds = 12;
    for (var seed = 1; seed <= seeds; seed++) {
      final run = playBot(GameState(seed: seed), prudent: true, check: _invariants);
      if (run.rounds >= 100) long++;
    }
    expect(long, greaterThanOrEqualTo((seeds * 0.8).ceil()));
  });

  test('الحملة نفسها بنفس البذرة تعطي نفس النتيجة تماما', () {
    final a = GameState(seed: 9);
    final b = GameState(seed: 9);
    final ra = playBot(a, prudent: true, maxRounds: 60);
    final rb = playBot(b, prudent: true, maxRounds: 60);
    expect(ra.rounds, equals(rb.rounds));
    expect(a.treasury, equals(b.treasury));
    expect(a.stability, equals(b.stability));
    expect(a.econ.grain, equals(b.econ.grain));
  });

  test('بذور مختلفة تعطي أحداثا مختلفة', () {
    final a = GameState(seed: 1);
    final b = GameState(seed: 2);
    playBot(a, prudent: true, maxRounds: 80);
    playBot(b, prudent: true, maxRounds: 80);
    expect(a.econ.grain == b.econ.grain && a.treasury == b.treasury, isFalse);
  });
}
