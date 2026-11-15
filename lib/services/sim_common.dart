import 'dart:math';

import '../models/game_state.dart';

/// أول سنتين (4 أنصاف) بلا أحداث عشوائية: يتعلم اللاعب الأنظمة قبل أن تضربه المفاجآت.
const int graceRounds = 4;

bool inGrace(GameState s) => s.round < graceRounds;

/// مولد أرقام عشوائي حتمي: نفس الحفظ ونفس الجولة يعطيان نفس الأحداث دائما.
Random rngFor(GameState s, int salt) =>
    Random((s.seed * 7919 + s.round * 104729 + salt * 31) & 0x7fffffff);

/// تكلفة الإجراءات تقاس بنسبة من الإيراد السنوي حتى تكبر مع الدولة.
double costShare(GameState s, double share) => (s.budget.totalRevenue * share).roundToDouble();

/// نتيجة إجراء من الديوان.
class CourtResult {
  final bool ok;
  final String message;
  const CourtResult(this.ok, this.message);
}

/// تجزئة ثابتة للنص (hashCode غير مضمون الثبات بين المنصات).
int stableHash(String s) {
  var h = 7;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}

/// السنة الميلادية لنصف سنة معين (0 = النصف الأول من 1800).
int yearOfRound(int round) => 1800 + round ~/ 2;
