import 'package:ottoman_empire_1800/engine/calibrator.dart';
import 'package:ottoman_empire_1800/engine/game_engine.dart';
import 'package:ottoman_empire_1800/models/game_state.dart';
import 'package:ottoman_empire_1800/models/round_plan.dart';
import 'package:ottoman_empire_1800/services/powers.dart';

const DecisionOption _neutral = DecisionOption(text: 'محايد', result: 'لا شيء');

/// جولة بلا أي أثر: لاعب لا يفعل شيئا.
RoundPlan neutralPlan() {
  Decision d(DecisionCategory c) => Decision(
    category: c,
    title: 't',
    scene: 's',
    dilemma: 'd',
    options: const [_neutral, _neutral, _neutral],
  );
  return RoundPlan(
    headline: 'h',
    briefing: 'b',
    decisions: [for (final c in DecisionCategory.values) d(c)],
  );
}

/// جولة بأسعار وخيارات واقعية (إصلاح/ترضية/تشدد، تقشف/ضريبة/لا شيء، هدية/حياد/استعراض).
RoundPlan realisticPlan() {
  Decision d(DecisionCategory c, List<DecisionOption> o) =>
      Decision(category: c, title: 't', scene: 's', dilemma: 'd', options: o);
  return RoundPlan(
    headline: 'h',
    briefing: 'b',
    decisions: [
      d(DecisionCategory.internal, const [
        DecisionOption(text: 'إصلاح', result: 'ن', cost: 400000, now: Effects(legitimacy: 1, stability: -1), later: Effects(army: 2), delay: 2),
        DecisionOption(text: 'ترضية', result: 'ن', cost: 300000, now: Effects(stability: 1), powerMood: {'janissaries': 6}),
        DecisionOption(text: 'تشدد', result: 'ن', now: Effects(stability: 2, legitimacy: -2)),
      ]),
      d(DecisionCategory.economy, const [
        DecisionOption(text: 'تقشف', result: 'ن', now: Effects(stability: -1, legitimacy: -1), delay: 1, lineChanges: [LineChange('palace', -500000)]),
        DecisionOption(text: 'ضريبة', result: 'ن', now: Effects(stability: -1), delay: 2, lineChanges: [LineChange('land', 600000)]),
        DecisionOption(text: 'لا شيء', result: 'ن'),
      ]),
      d(DecisionCategory.foreign, const [
        DecisionOption(text: 'هدية', result: 'ن', cost: 250000, now: Effects(foreign: 1), relations: {'britain': 4}),
        DecisionOption(text: 'حياد', result: 'ن'),
        DecisionOption(text: 'استعراض', result: 'ن', cost: 500000, now: Effects(army: 1, foreign: 1)),
      ]),
    ],
  );
}

/// نتيجة لعب آلي.
class BotRun {
  BotRun(this.rounds, this.ending);
  final int rounds;
  final Ending? ending;
}

/// لاعب آلي: [prudent] يتصرف كلاعب حذر (ضريبة عند نقص الخزينة، ترضية عند هبوط الاستقرار...)،
/// وغير ذلك لا يفعل شيئا. يتحقق من سلامة الأرقام في كل جولة.
BotRun playBot(GameState s, {required bool prudent, int maxRounds = 230, void Function(GameState)? check}) {
  final engine = GameEngine();
  var r = 0;
  for (; r < maxRounds; r++) {
    if (prudent) {
      s.plan = Calibrator.calibrate(realisticPlan(), s);
      final rev = s.budget.totalRevenue;
      final halfRev = rev / 2;
      final jan = s.powers['janissaries']!;
      final internal = (s.stability < 52 || (jan.satisfaction < 35 && !jan.dissolved)) ? 1 : 0;
      var econ = 2;
      if (s.treasury < 0.6 * halfRev || s.debt / rev > 1.2) {
        econ = (s.econ.avgMood < 42 || s.budget.lineValue('palace') > 1.5e6 * s.econ.priceIndex) ? 0 : 1;
      }
      final foreign = s.foreign < 35 ? 2 : 1;
      s.picks = [internal, econ, foreign];
      if (s.treasury > 1.5 * halfRev) s.repay = s.treasury - halfRev;
      if (jan.satisfaction < 30 && !jan.dissolved && s.courtActions > 0) PowerRules.appease(s, 'janissaries');
    } else {
      s.plan = Calibrator.calibrate(neutralPlan(), s);
      s.picks = [0, 0, 0];
    }
    final report = engine.resolveRound(s);
    check?.call(s);
    if (report.ending != null) return BotRun(r + 1, report.ending);
  }
  return BotRun(r, null);
}
