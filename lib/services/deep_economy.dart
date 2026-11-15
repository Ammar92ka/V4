import '../models/game_state.dart';
import '../models/systems.dart';

/// الاقتصاد العميق: مزاج الولايات، سعر الحبوب، التضخم، الفساد، السكان والمدارس.
/// كله محسوب بقواعد ثابتة، فلا يستهلك توكنات.
class DeepEconomyRules {
  DeepEconomyRules._();

  /// كلفة بناء مدرسة ابتدائية بأسعار 1800 (قروش).
  static const double schoolCost = 1600;

  /// الحصة من الإنفاق المدني التي تذهب لبناء المدارس.
  static const double schoolShare = 0.30;

  /// أقصى تضخم سنوي.
  static const double maxInflation = 10;

  /// أثر تغيير بند من الميزانية (عند سريانه فعلا) على الولايات والفساد.
  static void onLineChange(GameState s, String line, double delta) {
    final rev = s.budget.totalRevenue;
    if (rev <= 0 || delta == 0 || !delta.isFinite) return;
    final share = delta / rev;
    if (line == 'land' || line == 'provinces' || line == 'other') {
      // رفع الضرائب يغضب الولايات؛ تخفيفها يرضيها لكن بأثر أضعف
      final d = share > 0 ? -share * 60 : -share * 30;
      for (final p in s.econ.provinces.values) {
        if (!p.isLost) p.mood = clampD(p.mood + d, 0, 100);
      }
    } else if (line == 'admin') {
      s.econ.corruption = clampD(s.econ.corruption - share * 10, 5, 95);
    }
  }

  /// النمو الاسمي لنصف السنة: يرفع بنود الميزانية ومؤشر الأسعار معا.
  static void applyNominalGrowth(GameState s) {
    final g = s.econ.nominalGrowth;
    s.budget.grow(g);
    s.econ.priceIndex *= 1 + g;
  }

  /// خطوة نصف السنة. [net] صافي الميزانية قبل الاقتراض الطارئ.
  /// يعيد ملاحظات للتقرير.
  static List<String> step(GameState s, {required double net}) {
    final e = s.econ;
    final notes = <String>[];

    if (net < 0) {
      e.deficitStreak += 1;
      e.surplusStreak = 0;
    } else {
      e.surplusStreak += 1;
      e.deficitStreak = 0;
    }

    // التضخم: العجز المزمن يغذيه (طباعة وتخفيض عيار)، والفائض يبرده
    if (e.deficitStreak >= 3) {
      e.inflation += 0.35;
    } else if (net >= 0 && e.inflation > 2) {
      e.inflation -= 0.4;
    }
    if (e.grain > 150) e.inflation += 0.3;
    e.inflation = clampD(e.inflation, 1, maxInflation);
    if (e.deficitStreak == 4) {
      notes.add('أزمة نقدية: العجز المتواصل يضعف العملة ويرفع الأسعار');
    }

    // مزاج الولايات
    for (final p in e.provinces.values) {
      if (p.isLost) continue;
      // الاستقرار يهدئ الولايات، والناس يعتادون: المزاج يميل ببطء إلى أصله
      var d = 0.05 * (s.stability - 55) + 0.03 * (p.def.mood - p.mood);
      if (e.grain > 130) {
        d -= (e.grain - 130) / 40;
      } else if (e.grain < 90) {
        d += 0.5;
      }
      p.mood = clampD(p.mood + d, 0, 100);
      if (p.mood < 15) notes.add('اضطرابات وتمرد في ${p.name}');
    }

    // الفساد: يزيد عند إهمال الإدارة وبنفوذ الملتزمين، ويقل بالإدارة القوية والتعليم
    final rev = s.budget.totalRevenue;
    if (rev > 0) {
      final adminShare = s.budget.lineValue('admin') / rev;
      var c = 0.0;
      if (adminShare < 0.20) c += 0.5;
      if (adminShare > 0.30) c -= 0.5;
      final farmers = s.powers['tax_farmers'];
      if (farmers != null && !farmers.dissolved && farmers.influence > 70) c += 0.3;
      if (s.education > 40) c -= 0.2;
      e.corruption = clampD(e.corruption + c, 5, 95);
    }

    _demography(s);
    return notes;
  }

  static void _demography(GameState s) {
    final d = s.demog;
    final e = s.econ;
    // السكان: نمو سنوي نحو 0.4% يتأثر بالاستقرار والمجاعات
    var g = 0.0020 + 0.00001 * (s.stability - 55);
    if (e.grain > 130) g -= 0.0008 * ((e.grain - 130) / 50);
    g = g < -0.005 ? -0.005 : g;
    d.population = clampD(d.population * (1 + g), 1, 500);

    // المدارس: حصة من الإنفاق المدني تبني مدارس بسعر يتضخم
    final civilHalf = s.budget.lineValue('civil') / 2;
    final newSchools = civilHalf * schoolShare / (schoolCost * e.priceIndex);
    d.schools = clampD(d.schools + newSchools, 0, 1e7);

    // نسبة التعلم: تزيد بالتعليم وبكثافة المدارس
    final perMillion = d.schools / d.population;
    final dl = (0.02 + 0.0008 * (s.education - 15) + 0.00002 * (perMillion - 346))
        .clamp(-0.02, 0.15)
        .toDouble();
    d.literacy = clampD(d.literacy + dl, 1, 80);
  }
}
