import '../models/game_state.dart';
import 'economy.dart';

/// قواعد الاستقرار: كل بعد من الستة يتحرك بأسبابه، والكلي متوسطها.
/// كل الانجرافات تساوي صفرا في الظروف الابتدائية، فلا يتغير شيء بلا سبب.
class StabilityRules {
  StabilityRules._();

  /// يطبق انجراف نصف السنة. يعيد ملاحظات للتقرير.
  static List<String> step(GameState s, {required double debtRatio, required bool emergency}) {
    final st = s.stab;
    final e = s.econ;
    final notes = <String>[];

    // الدين الثقيل: يضرب الاقتصاد أكثر من غيره (المجموع كخصم الاستقرار القديم)
    final u = EconomyRules.debtUnrest(debtRatio).toDouble();
    if (u > 0) {
      st.shift('economic', -3 * u);
      st.shift('social', -1.5 * u);
      st.shift('political', -1.5 * u);
    }

    // الاقتصاد
    if (e.deficitStreak >= 8) {
      st.shift('economic', -2);
    } else if (e.deficitStreak >= 4) {
      st.shift('economic', -1);
    }
    if (e.inflation > 8) st.shift('economic', -1);
    if (e.surplusStreak >= 3 && debtRatio < 1.5) st.shift('economic', 1);

    // الاجتماع
    if (e.grain >= 180) {
      st.shift('social', -2);
      notes.add('مجاعة وغلاء فاحش يهزان المجتمع');
    } else if (e.grain >= 140) {
      st.shift('social', -1);
    }
    final mood = e.avgMood;
    if (mood < 35) st.shift('social', -1);
    if (mood > 65 && e.grain < 110) st.shift('social', 1);

    // الجيش
    final jan = s.powers['janissaries'];
    if (jan != null && !jan.dissolved && jan.satisfaction < 25) st.shift('military', -1);
    if (s.army < 25) st.shift('military', -1);

    // السياسة
    if (s.legitimacy < 35) st.shift('political', -1);
    if (s.legitimacy > 75) st.shift('political', 1);
    if (_avgDanger(s) > 70) st.shift('political', -1);

    // الدين
    final ulema = s.powers['ulema'];
    if (ulema != null && !ulema.dissolved) {
      if (ulema.satisfaction < 30) st.shift('religious', -1);
      if (ulema.satisfaction > 70) st.shift('religious', 1);
    }

    // الأقاليم
    if (mood < 35) st.shift('regional', -1);
    if (mood > 65) st.shift('regional', 1);
    if (e.provinces.values.any((p) => !p.isLost && p.mood < 20)) st.shift('regional', -1);
    final gov = s.powers['governors'];
    if (gov != null && !gov.dissolved && gov.satisfaction < 30) st.shift('regional', -1);

    return notes;
  }

  /// متوسط خطر القوى الفاعلة.
  static double _avgDanger(GameState s) {
    final active = s.powers.values.where((p) => !p.dissolved).toList();
    if (active.isEmpty) return 0;
    return active.fold(0.0, (a, p) => a + p.danger) / active.length;
  }

  static double averageDanger(GameState s) => _avgDanger(s);
}
