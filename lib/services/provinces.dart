import '../models/game_state.dart';
import '../models/systems.dart';
import 'sim_common.dart';

/// الولايات: ميل الانفصال، الحكم الذاتي، التمرد، والاستقلال أو الفقدان.
/// الإيراد يتأثر تلقائيا بوزن الولايات الفعالة (انظر EconomyState.revenueMultiplier).
class ProvinceRules {
  ProvinceRules._();

  /// الحكم الذاتي الذي تصير عنده الولاية شبه مستقلة، وما تعود عنده موالية.
  static const double autonomousAt = 70;
  static const double loyalBelow = 50;

  /// الحد الذي تبدأ عنده محاولات الاستقلال.
  static const double secessionAt = 95;

  static const double suppressShare = 0.020;
  static const double privilegesShare = 0.015;

  /// الوزن الفعال المتبقي؛ دون هذا الحد تتفكك الإمبراطورية.
  static const double dismemberedBelow = 0.40;

  static List<ProvinceState> lost(GameState s) =>
      [for (final p in s.econ.provinces.values) if (p.isLost) p];

  static List<String> step(GameState s) {
    final notes = <String>[];
    final rng = rngFor(s, 21);
    final atWar = s.wars.isNotEmpty;
    final threatened = s.countries.values.any(
      (c) => c.relation < 30 && c.military > s.army,
    );
    for (final p in s.econ.provinces.values) {
      if (p.isLost) continue;
      final d = p.def;
      var f = 0.5 + (50 - p.mood) / 50 + (55 - s.legitimacy) / 100;
      if (atWar) f += 0.3;
      if (threatened && (p.key == 'rumelia' || p.key == 'egypt' || p.key == 'syria')) f += 0.2;
      if (s.army > 60) f -= 0.15;
      if (p.key == 'egypt') {
        final m = s.powers['mamluks'];
        if (m != null && !m.dissolved) f += (m.influence - 50) / 200;
      }
      var gain = d.sep * (f < -0.3 ? -0.3 : f);
      if (gain > 0) gain *= s.diff.events;
      p.autonomy = clampD(p.autonomy + gain, 0, 100);

      if (p.status == ProvinceState.loyal && p.autonomy >= autonomousAt) {
        p.status = ProvinceState.autonomousStatus;
        notes.add('أعلنت ${p.name} حكما ذاتيا وصارت تدفع جزءا من إيرادها فقط');
      } else if (p.status == ProvinceState.autonomousStatus && p.autonomy < loyalBelow) {
        p.status = ProvinceState.loyal;
        notes.add('عادت ${p.name} إلى الولاء الكامل');
      }

      if (!inGrace(s) && p.autonomy >= secessionAt) {
        if (rng.nextDouble() < 0.30 * s.diff.events) {
          final crushed = s.army >= 55 && s.wars.isEmpty;
          if (crushed) {
            p.autonomy = 70;
            p.mood = clampD(p.mood - 10, 0, 100);
            s.treasury = (s.treasury - costShare(s, 0.05)).clamp(0.0, double.infinity).toDouble();
            s.stab.shift('political', -2);
            s.army = (s.army - 2).clamp(0, 100).toInt();
            notes.add('قمع جيشنا محاولة انفصال ${p.name} بكلفة باهظة');
          } else {
            notes.add(lose(s, p, how: 'independence'));
          }
        }
      }
    }
    return notes;
  }

  /// فقدان ولاية (استقلال أو تنازل). يعيد جملة للتقرير.
  static String lose(GameState s, ProvinceState p, {required String how}) {
    p.status = ProvinceState.independent;
    p.autonomy = 100;
    s.demog.population = clampD(s.demog.population * (1 - p.def.weight * 0.9), 1, 500);
    s.legitimacy = (s.legitimacy - 6).clamp(0, 100).toInt();
    s.foreign = (s.foreign - 3).clamp(0, 100).toInt();
    s.stab.shift('regional', -4);
    s.stab.shift('political', -3);
    return how == 'cession'
        ? 'تنازلت الدولة عن ${p.name} بمعاهدة الصلح'
        : 'انفصلت ${p.name} واستقلت عن الدولة';
  }

  static CourtResult _check(GameState s, ProvinceState? p, double cost) {
    if (p == null) return const CourtResult(false, 'ولاية غير معروفة');
    if (p.isLost) return CourtResult(false, '${p.name} مفقودة');
    if (s.courtActions <= 0) return const CourtResult(false, 'استنفدت إجراءات الديوان لنصف السنة هذا');
    if (s.treasury < cost) return const CourtResult(false, 'الخزينة لا تكفي');
    return const CourtResult(true, '');
  }

  /// قمع الاضطراب: يخفض الحكم الذاتي لكن يغضب الأهالي ويكلف جنودا.
  static CourtResult suppress(GameState s, String key) {
    final p = s.econ.provinces[key];
    final cost = costShare(s, suppressShare);
    final chk = _check(s, p, cost);
    if (!chk.ok) return chk;
    s.treasury -= cost;
    s.courtActions -= 1;
    p!.autonomy = clampD(p.autonomy - 15, 0, 100);
    p.mood = clampD(p.mood - 5, 0, 100);
    s.army = (s.army - 1).clamp(0, 100).toInt();
    s.courtLog.add('قمع الاضطراب في ${p.name}');
    return CourtResult(true, 'خف ميل ${p.name} إلى الانفصال لكن غضب أهلها');
  }

  /// منح امتيازات: ترضي الأهالي وتخفض الحكم الذاتي قليلا.
  static CourtResult privileges(GameState s, String key) {
    final p = s.econ.provinces[key];
    final cost = costShare(s, privilegesShare);
    final chk = _check(s, p, cost);
    if (!chk.ok) return chk;
    s.treasury -= cost;
    s.courtActions -= 1;
    p!.autonomy = clampD(p.autonomy - 8, 0, 100);
    p.mood = clampD(p.mood + 8, 0, 100);
    s.courtLog.add('امتيازات لـ${p.name}');
    return CourtResult(true, 'ارتاحت ${p.name} لامتيازاتك');
  }
}
