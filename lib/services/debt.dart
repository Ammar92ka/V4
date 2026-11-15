import '../models/game_state.dart';
import '../models/systems.dart';
import 'economy.dart';
import 'projects.dart';
import 'sim_common.dart';

/// الدين الأقرب للواقع: داخلي وخارجي، تصنيف ائتماني، عجز عن السداد (كما في 1875)،
/// وإدارة ديون عامة تحصّل جزءا من الإيراد للدائنين (كما في 1881).
class DebtRules {
  DebtRules._();

  /// من هذه السنة تأتي القروض من الدائنين الأجانب (أول قرض خارجي 1854).
  static const int foreignFrom = 1854;
  static const double foreignShare = 0.7;

  /// نصيب إدارة الديون العامة من الإيراد، وأنصاف سنوات تعليق الفوائد بعد العجز.
  static const double dadShare = 0.20;
  static const int moratoriumHalves = 4;

  /// أنصاف السنة التي يبقى فيها أثر العجز على التصنيف.
  static const int defaultMemory = 40;

  static double internalDebt(GameState s) => (s.debt - s.foreignDebt).clamp(0.0, double.infinity).toDouble();

  static const List<String> _lenders = ['britain', 'france', 'austria', 'germany'];

  /// تصنيف ائتماني من 5 إلى 95 (75 عند البدء).
  static double creditRating(GameState s) {
    final rev = s.budget.totalRevenue;
    final ratio = rev > 0 ? s.debt / rev : 10.0;
    var rel = 0.0;
    var n = 0;
    for (final k in ['britain', 'france', 'austria']) {
      rel += s.countries[k]?.relation ?? 48;
      n++;
    }
    final avg = n == 0 ? 48 : rel / n;
    var r = 75 - 12 * (ratio - 0.33) + 0.4 * (avg - 48);
    if (ProjectRules.hasPerk(s, 'credit')) r += 10;
    if (s.defaultRound >= 0 && s.round - s.defaultRound < defaultMemory) r -= 30;
    return clampD(r, 5, 95);
  }

  /// فائدة الدين الخارجي: أرخص عند تصنيف أعلى.
  static double foreignRate(GameState s) => 0.05 + 0.10 * (1 - creditRating(s) / 100);

  static bool inMoratorium(GameState s) =>
      s.defaultRound >= 0 && s.round - s.defaultRound < moratoriumHalves;

  /// فوائد نصف السنة: الداخلي بفائدة ثابتة وعلاوة تضخم، والخارجي بحسب التصنيف.
  static double halfYearInterest(GameState s) {
    final internal = EconomyRules.halfYearInterest(internalDebt(s), inflation: s.econ.inflation);
    final foreign = inMoratorium(s) ? 0.0 : s.foreignDebt * foreignRate(s) / 2;
    return internal + foreign;
  }

  /// يضيف قرضا إلى الدين، والجزء الأجنبي منه حسب العصر.
  static void addLoan(GameState s, double amount) {
    if (amount <= 0 || !amount.isFinite) return;
    s.debt += amount;
    if (yearOfRound(s.round) >= foreignFrom && !inMoratorium(s)) {
      s.foreignDebt += amount * foreignShare;
    }
  }

  /// يضيف دينا أجنبيا مباشرة (تعويض حرب).
  static void addForeign(GameState s, double amount) {
    if (amount <= 0 || !amount.isFinite) return;
    s.debt += amount;
    s.foreignDebt += amount;
  }

  /// يسدد من الخزينة: الداخلي أولا (فائدته أعلى) ثم الأجنبي. يعيد المسدد فعلا.
  static double repay(GameState s, double amount) {
    if (amount <= 0) return 0;
    var paid = amount;
    if (paid > s.debt) paid = s.debt;
    if (paid > s.treasury) paid = s.treasury;
    if (paid <= 0) return 0;
    final internal = internalDebt(s);
    final foreignPaid = paid > internal ? paid - internal : 0.0;
    s.treasury -= paid;
    s.debt -= paid;
    s.foreignDebt = (s.foreignDebt - foreignPaid).clamp(0.0, s.debt).toDouble();
    return paid;
  }

  /// ما تحصّله إدارة الديون العامة من إيراد نصف السنة (يخصم من الخزينة ويسدد الدين الأجنبي).
  static double dadPayment(GameState s, double halfRevenue) {
    if (!s.dadActive || s.foreignDebt <= 0) return 0;
    var pay = halfRevenue * dadShare;
    if (pay > s.foreignDebt) pay = s.foreignDebt;
    if (pay <= 0) return 0;
    s.foreignDebt -= pay;
    s.debt = (s.debt - pay).clamp(0.0, double.infinity).toDouble();
    return pay;
  }

  /// يفحص العجز عن السداد وإدارة الديون العامة. يستدعى بعد تحديث [GameState.emergencyStreak].
  static List<String> step(GameState s) {
    final notes = <String>[];
    final rev = s.budget.totalRevenue;
    final canDefault = s.defaultRound < 0 || s.round - s.defaultRound > defaultMemory;
    if (canDefault && s.foreignDebt > 0.5 * rev && s.emergencyStreak >= 3) {
      s.defaultRound = s.round;
      s.dadActive = false;
      for (final k in _lenders) {
        final c = s.countries[k];
        if (c != null) c.relation = clampD(c.relation - 15, 0, 100);
      }
      s.legitimacy = (s.legitimacy - 4).clamp(0, 100).toInt();
      s.stab.shift('political', -3);
      notes.add('أعلنت الدولة عجزها عن سداد الديون الخارجية وعلقت الفوائد، فغضب الدائنون');
    }
    if (s.defaultRound >= 0 &&
        !s.dadActive &&
        s.round - s.defaultRound >= moratoriumHalves &&
        s.round - s.defaultRound <= defaultMemory &&
        s.foreignDebt > 0.2 * rev) {
      s.dadActive = true;
      s.legitimacy = (s.legitimacy - 2).clamp(0, 100).toInt();
      for (final k in _lenders) {
        final c = s.countries[k];
        if (c != null) c.relation = clampD(c.relation + 10, 0, 100);
      }
      notes.add('أنشئت إدارة للديون العامة تحصّل ${(dadShare * 100).round()}% من الإيراد للدائنين');
    }
    if (s.dadActive && s.foreignDebt <= 0.2 * rev) {
      s.dadActive = false;
      notes.add('أتمت إدارة الديون العامة ما عليها وأنهت إشرافها على الإيرادات');
    }
    return notes;
  }
}
