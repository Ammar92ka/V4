import 'dart:math';

import '../models/game_state.dart';
import '../models/systems.dart';
import 'projects.dart';
import 'sim_common.dart';

/// المناخ والكوارث: جفاف وفيضان وطاعون ووفرة. يجري قبل حساب الإيراد
/// فيدخل أثر المحصول في جباية نصف السنة نفسه.
class ClimateRules {
  ClimateRules._();

  static List<String> step(GameState s) {
    final e = s.econ;
    final notes = <String>[];
    for (final p in e.provinces.values) {
      p.harvest = 1.0;
    }
    // سعر الحبوب يعود تدريجيا إلى المعتاد
    e.grain += (100 - e.grain) * 0.2;
    if (!inGrace(s)) {
      final rng = rngFor(s, 3);
      final m = s.diff.events;
      final r = rng.nextDouble();
      if (r < 0.10 * m) {
        final a = _pick(rng, e);
        final hit = <ProvinceState>[a];
        if (rng.nextDouble() < 0.4) {
          final b = _pick(rng, e);
          if (b.key != a.key) hit.add(b);
        }
        final resist = ProjectRules.hasPerk(s, 'drought');
        for (final p in hit) {
          p.harvest = resist ? 0.8 : 0.65;
        }
        e.grain += resist ? 20 : 35;
        notes.add('جفاف في ${hit.map((p) => p.name).join(' و')} يضرب المحصول ويرفع الأسعار');
      } else if (r < 0.15 * m) {
        final p = _pick(rng, e);
        p.harvest = 0.8;
        p.mood = clampD(p.mood - 2, 0, 100);
        notes.add('فيضانات في ${p.name} تتلف الحقول');
      } else if (r < 0.19 * m) {
        final p = _pick(rng, e);
        final resist = ProjectRules.hasPerk(s, 'plague');
        p.mood = clampD(p.mood - (resist ? 2 : 4), 0, 100);
        s.demog.population = clampD(s.demog.population * (resist ? 0.997 : 0.994), 1, 500);
        s.stab.shift('social', resist ? -1 : -2);
        notes.add('طاعون في ${p.name} يحصد الناس ويشل التجارة');
      } else if (r < 0.27 * m) {
        for (final p in e.provinces.values) {
          p.harvest = 1.1;
        }
        e.grain -= 15;
        notes.add('موسم وفير يخفض أسعار الحبوب');
      } else if (r < 0.30 * m) {
        final p = _pick(rng, e);
        p.harvest = 0.8;
        e.grain += 15;
        notes.add('جراد وصقيع في ${p.name} ينقصان الغلة');
      }
    }
    e.grain = clampD(e.grain, 60, 260);
    return notes;
  }

  /// اختيار ولاية بوزنها السكاني.
  static ProvinceState _pick(Random rng, EconomyState e) {
    final live = [for (final p in e.provinces.values) if (!p.isLost) p];
    if (live.isEmpty) return e.provinces.values.first;
    final total = live.fold(0.0, (a, p) => a + p.def.weight);
    var x = rng.nextDouble() * total;
    for (final p in live) {
      x -= p.def.weight;
      if (x <= 0) return p;
    }
    return live.last;
  }
}

/// الاستخبارات: تقارير عن الدول وعن القوى الداخلية، بدرجات موثوقية.
/// قد يكذب التقرير، والحقيقة تنكشف بعد نصف سنة فيتعلم اللاعب من يثق به.
class SpyRules {
  SpyRules._();

  static const List<double> _foreignChance = [0, 0.5, 0.7, 0.9];
  static const List<double> _foreignAccuracy = [0, 0.55, 0.75, 0.9];
  static const List<double> _domesticChance = [0, 0.6, 0.85];
  static const List<double> _domesticAccuracy = [0, 0.6, 0.85];
  static const int maxKept = 8;

  static List<String> step(GameState s) {
    final notes = <String>[];

    // كشف حقيقة تقارير النصف السابق
    for (final r in s.intel) {
      if (!r.revealed && r.round < s.round) {
        r.revealed = true;
        notes.add('تبين أن ${r.truth ? 'صحة' : 'كذب'} تقرير الاستخبارات: ${r.claim}');
      }
    }

    // تقارير جديدة عن الدول
    var i = 0;
    for (final c in s.countries.values) {
      i++;
      final q = c.intelQuality.clamp(0, 3).toInt();
      if (q == 0) continue;
      final rng = rngFor(s, 400 + i);
      if (rng.nextDouble() >= _foreignChance[q]) continue;
      final hostile = c.relation < 35;
      final truthful = rng.nextDouble() < _foreignAccuracy[q];
      final claimsHostile = truthful ? hostile : !hostile;
      final claim = claimsHostile
          ? '${c.name} تحشد قواتها وتجهز لحرب ضدنا'
          : '${c.name} لا تنوي الحرب علينا وتميل للمهادنة';
      s.intel.add(
        SpyReport(
          round: s.round,
          target: c.key,
          claim: claim,
          reliability: (_foreignAccuracy[q] * 100).round(),
          truth: truthful,
        ),
      );
      notes.add('تقرير استخبارات (موثوقية ${(_foreignAccuracy[q] * 100).round()}%): $claim');
    }

    // تقرير داخلي عن أخطر قوة
    final lvl = s.domesticSpy.clamp(0, 2).toInt();
    if (lvl > 0) {
      final active = s.powers.values.where((p) => !p.dissolved).toList()
        ..sort((a, b) => b.danger.compareTo(a.danger));
      if (active.isNotEmpty) {
        final rng = rngFor(s, 450);
        if (rng.nextDouble() < _domesticChance[lvl]) {
          final top = active.first;
          final real = top.danger >= 55;
          final truthful = rng.nextDouble() < _domesticAccuracy[lvl];
          final claimsPlot = truthful ? real : !real;
          final claim = claimsPlot
              ? '${top.name} تدبر شيئا ضد العرش'
              : '${top.name} هادئة ولا تنوي شيئا';
          s.intel.add(
            SpyReport(
              round: s.round,
              target: 'domestic',
              claim: claim,
              reliability: (_domesticAccuracy[lvl] * 100).round(),
              truth: truthful,
            ),
          );
          notes.add('تقرير استخبارات داخلي (موثوقية ${(_domesticAccuracy[lvl] * 100).round()}%): $claim');
        }
      }
    }

    if (s.intel.length > maxKept) {
      s.intel.removeRange(0, s.intel.length - maxKept);
    }
    return notes;
  }
}
