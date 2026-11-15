import 'package:flutter_test/flutter_test.dart';
import 'package:ottoman_empire_1800/models/game_state.dart';
import 'package:ottoman_empire_1800/models/systems.dart';
import 'package:ottoman_empire_1800/services/ai_provider.dart';
import 'package:ottoman_empire_1800/services/round_generator.dart';
import 'package:ottoman_empire_1800/services/round_prompt.dart';

import 'support/fake_ai.dart';

Future<void> _noWait(Duration _) async {}

void main() {
  group('طلب الجولة', () {
    test('يحتوي التاريخ والميزانية ومفاتيح البنود والمرجع التاريخي', () {
      final prompt = buildRoundPrompt(GameState());
      expect(prompt.contains('1800'), isTrue);
      expect(prompt.contains('customs'), isTrue);
      expect(prompt.contains('army'), isTrue);
      expect(prompt.contains('1798'), isTrue);
      expect(prompt.contains('JSON'), isTrue);
    });

    test('المرجع التاريخي يقتصر على ما يقرب السنة الحالية لتوفير التوكنات', () {
      final early = buildRoundPrompt(GameState());
      expect(early.contains('1826'), isFalse);
      expect(early.contains('1909'), isFalse);
      final mid = buildRoundPrompt(GameState(round: 48));
      expect(mid.contains('1826'), isTrue);
      expect(mid.contains('1798'), isFalse);
    });

    test('يحتوي آخر القرارات والذاكرة والتقرير السابق', () {
      final s = GameState(
        round: 3,
        chronicle: 'ذاكرة خاصة ABC',
        lastReport: 'تقرير خاص XYZ',
        history: const [
          HistoryEntry(round: 2, category: 'اقتصاد', title: 'عنوان خاص', choice: 'اختيار خاص'),
        ],
      );
      final prompt = buildRoundPrompt(s);
      expect(prompt.contains('ذاكرة خاصة ABC'), isTrue);
      expect(prompt.contains('تقرير خاص XYZ'), isTrue);
      expect(prompt.contains('اختيار خاص'), isTrue);
      expect(prompt.contains('تموز - كانون الأول 1801'), isTrue);
    });

    test('يرسل آخر 9 قرارات فقط (ثلاث جولات)', () {
      final history = [
        for (var i = 0; i < 40; i++)
          HistoryEntry(round: i, category: 'ف', title: 'عنوان$i', choice: 'اختيار$i'),
      ];
      final prompt = buildRoundPrompt(GameState(round: 40, history: history));
      expect(prompt.contains('اختيار39'), isTrue);
      expect(prompt.contains('اختيار31'), isTrue);
      expect(prompt.contains('اختيار30'), isFalse);
    });

    test('الجزء الثابت في أول الطلب ليستفيد المزود من التخزين المؤقت', () {
      final a = buildRoundPrompt(GameState());
      final b = buildRoundPrompt(GameState(round: 40, treasury: 1, debt: 99, legitimacy: 20));
      var n = 0;
      while (n < a.length && n < b.length && a[n] == b[n]) {
        n++;
      }
      expect(n, greaterThan(1500));
    });

    test('حجم الطلب في منتصف الحملة يبقى مضغوطا', () {
      final history = [
        for (var i = 0; i < 60; i++)
          HistoryEntry(
            round: i ~/ 3,
            category: 'سياسة داخلية',
            title: 'عنوان قرار طويل نسبيا هنا',
            choice: 'نص خيار اللاعب الذي يصف قرارا مفصلا يمتد لجملتين تقريبا مع تفاصيل التنفيذ والتكلفة المتوقعة ' * 2,
          ),
      ];
      final s = GameState(
        round: 80,
        history: history,
        chronicle: 'ملاحظة ' * 400,
        lastReport: 'تقرير نصف السنة: إيراد 8.39م، نفقات 8.50م، فوائد 0.36م، صافي -0.47م.',
        world: WorldMemory(
          wars: List.filled(6, 'حرب جارية مع دولة كبرى على الحدود الشمالية والبحر الأسود'),
          alliances: List.filled(6, 'تحالف دفاعي مع بريطانيا لحماية المضائق والموانئ'),
          reforms: List.filled(6, 'إصلاح الجيش الجديد وتدريب الفرق على النظام الأوروبي'),
          promises: List.filled(6, 'وعد للأعيان بتخفيف الضرائب مقابل التجنيد'),
        ),
      );
      final prompt = buildRoundPrompt(s);
      expect(prompt.length, lessThan(9000));
    });

    test('يحتوي القوى والدول وتقارير الاستخبارات دون كشف حقيقتها', () {
      final s = GameState(
        intel: [
          SpyReport(round: 0, target: 'france', claim: 'فرنسا تحشد قواتها', reliability: 75, truth: false),
        ],
      );
      final prompt = buildRoundPrompt(s);
      expect(prompt.contains('الانكشارية'), isTrue);
      expect(prompt.contains('بريطانيا'), isTrue);
      expect(prompt.contains('فرنسا تحشد قواتها (75%)'), isTrue);
      expect(prompt.contains('تبين'), isFalse);
    });

    test('تنبيه المشكلة يضاف عند إعادة المحاولة', () {
      final prompt = buildRoundPrompt(GameState(), problem: 'خيار ناقص');
      expect(prompt.contains('خيار ناقص'), isTrue);
    });

    test('لا يحتوي مفتاحا ولا شيئا من الإعدادات', () {
      final prompt = buildRoundPrompt(GameState());
      expect(prompt.contains('AIza'), isFalse);
    });
  });

  group('RoundGenerator', () {
    test('ينجح من أول محاولة ويعاير الجولة', () async {
      final ai = FakeAi(seed: 3, wild: true);
      final gen = RoundGenerator(call: ai.call, wait: _noWait);
      final plan = await gen.generate(GameState());
      expect(plan.decisions.length, equals(3));
      expect(ai.calls, equals(1));
      final revenue = GameState().budget.totalRevenue;
      for (final d in plan.decisions) {
        for (final o in d.options) {
          expect(o.cost, lessThanOrEqualTo(revenue * 0.6 + 1));
          expect(o.loan, lessThanOrEqualTo(revenue + 1));
        }
      }
    });

    test('يعيد المحاولة عند رد غير صالح ويرسل سبب الرفض', () async {
      final prompts = <String>[];
      final good = FakeAi(seed: 2);
      var n = 0;
      final gen = RoundGenerator(
        call: (p) async {
          prompts.add(p);
          n++;
          if (n == 1) return 'ليس JSON';
          return good.call(p);
        },
        wait: _noWait,
      );
      final plan = await gen.generate(GameState());
      expect(plan.decisions.length, equals(3));
      expect(prompts.length, equals(2));
      expect(prompts.first.contains('تنبيه'), isFalse);
      expect(prompts.last.contains('تنبيه'), isTrue);
    });

    test('يعيد المحاولة عند خطأ مؤقت من المزود', () async {
      final good = FakeAi(seed: 2);
      var n = 0;
      final gen = RoundGenerator(
        call: (p) async {
          n++;
          if (n < 3) throw const AiException('ضغط', retryable: true);
          return good.call(p);
        },
        wait: _noWait,
      );
      final plan = await gen.generate(GameState());
      expect(plan.decisions.length, equals(3));
      expect(n, equals(3));
    });

    test('الخطأ غير المؤقت يرمى فورا بلا إعادة', () async {
      var n = 0;
      final gen = RoundGenerator(
        call: (p) async {
          n++;
          throw const AiException('مفتاح خاطئ');
        },
        wait: _noWait,
      );
      await expectLater(gen.generate(GameState()), throwsA(isA<AiException>()));
      expect(n, equals(1));
    });

    test('بعد استنفاد المحاولات يرمي خطأ مفهوما', () async {
      var n = 0;
      final gen = RoundGenerator(
        call: (p) async {
          n++;
          return 'ليس JSON';
        },
        maxAttempts: 2,
        wait: _noWait,
      );
      await expectLater(gen.generate(GameState()), throwsA(isA<AiException>()));
      expect(n, equals(2));
    });

    test('يبلغ الواجهة برقم المحاولة', () async {
      final seen = <int>[];
      var n = 0;
      final good = FakeAi(seed: 2);
      final gen = RoundGenerator(
        call: (p) async {
          n++;
          if (n == 1) return '{}';
          return good.call(p);
        },
        wait: _noWait,
        onAttempt: (a, _) => seen.add(a),
      );
      await gen.generate(GameState());
      expect(seen, equals([1, 2]));
    });
  });
}
