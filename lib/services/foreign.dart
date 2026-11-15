import '../models/game_state.dart';
import '../models/systems.dart';
import 'sim_common.dart';

/// اقتصادات الدول وقواها العسكرية: تنمو بمعدلات تاريخية تقريبية مع تقلب عشوائي حتمي.
/// المقياس واحد مع الدولة العثمانية (اقتصادنا 100 عند البدء، وجيشنا بمؤشرنا من 100).
class ForeignRules {
  ForeignRules._();

  /// اقتصادنا بمقياس الدول: الإيراد الحقيقي نسبة إلى 1800 × أثر الولايات والفساد.
  static double ottomanEconomy(GameState s) {
    final real = s.budget.totalRevenue / (s.econ.priceIndex <= 0 ? 1 : s.econ.priceIndex);
    return 100 * real / 18000000 * s.econ.revenueMultiplier;
  }

  static double ottomanMilitary(GameState s) => s.army.toDouble();

  static double econRatio(GameState s, CountryState c) {
    final ours = ottomanEconomy(s);
    return c.economy / (ours < 1 ? 1 : ours);
  }

  static double milRatio(GameState s, CountryState c) {
    final ours = ottomanMilitary(s);
    return c.military / (ours < 1 ? 1 : ours);
  }

  /// وصف نسبة القوة (قوتهم ÷ قوتنا).
  static String strengthLabel(double ratio) {
    if (ratio < 0.8) return 'أضعف منا';
    if (ratio < 1.25) return 'مقارب لنا';
    if (ratio < 2.0) return 'أقوى منا';
    return 'أقوى منا بكثير';
  }

  /// النمو السنوي للجيش مع أحداث العصر (نابليون، القرم، ألمانيا...).
  static double annualMilGrowth(String key, int year) {
    final base = countryDef(key)?.milGrowth ?? 0.0;
    var extra = 0.0;
    switch (key) {
      case 'france':
        if (year <= 1814) {
          extra = 0.02;
        } else if (year <= 1829) {
          extra = -0.06;
        }
      case 'russia':
        if (year >= 1854 && year <= 1856) {
          extra = -0.04;
        } else if (year >= 1857 && year <= 1870) {
          extra = -0.01;
        }
      case 'austria':
        if (year >= 1866) extra = -0.01;
      case 'germany':
        if (year >= 1860) extra = 0.025;
    }
    return base + extra;
  }

  static double annualEcoGrowth(String key, int year) {
    final base = countryDef(key)?.ecoGrowth ?? 0.0;
    var extra = 0.0;
    if (key == 'germany' && year >= 1850) extra = 0.012;
    if (key == 'austria' && year >= 1900) extra = 0.005;
    return base + extra;
  }

  /// نمو نصف السنة لكل دولة.
  static List<String> step(GameState s) {
    final year = yearOfRound(s.round);
    var i = 0;
    for (final c in s.countries.values) {
      i++;
      final rng = rngFor(s, 700 + i);
      final noiseE = (rng.nextDouble() - 0.5) * 0.006;
      final noiseM = (rng.nextDouble() - 0.5) * 0.010;
      c.economy = clampD(c.economy * (1 + annualEcoGrowth(c.key, year) / 2 + noiseE), 20, 5000);
      c.military = clampD(c.military * (1 + annualMilGrowth(c.key, year) / 2 + noiseM), 8, 300);
    }
    return const [];
  }
}
