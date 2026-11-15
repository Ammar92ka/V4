import '../data/history_anchors.dart';
import '../data/projects_catalog.dart';
import '../engine/calibrator.dart';
import '../engine/game_engine.dart';
import '../models/budget.dart';
import '../models/game_state.dart';
import '../models/systems.dart';
import 'diplomacy.dart';
import 'debt.dart';
import 'economy.dart';
import 'foreign.dart';
import 'wars.dart';

String _n(num v) => v.round().toString();

String _lines(List<BudgetLine> lines, Budget b) =>
    lines.map((l) => '${l.key}=${_n(b.lineValue(l.key))}').join('، ');

String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

/// آخر قرارات اللاعب: الجولة الأخيرة مفصلة وما قبلها مختصر، في حدود ثلاث جولات.
const int _historyEntries = 9;
const int _detailedEntries = 3;

/// يبني طلب الجولة. الذكاء الاصطناعي هو الكاتب الوحيد للأحداث والقرارات؛
/// اللعبة ترسل له الحالة والقواعد وتستقبل JSON تعايره بعد ذلك.
///
/// الترتيب مقصود: القواعد والنموذج (ثابتان) أولا ثم الحالة (متغيرة)،
/// فيستفيد المزود من التخزين المؤقت للبادئة المتكررة ويقل الاستهلاك.
String buildRoundPrompt(GameState s, {String? problem}) {
  final revenue = s.budget.totalRevenue;
  final ratio = EconomyRules.debtRatio(s.debt, s.budget);
  final year = GameEngine.yearOf(s.round);
  final buf = StringBuffer();

  // ───── القسم الثابت ─────
  buf
    ..writeln(
      'أنت راوٍ ومحكّم تاريخي للعبة الدولة العثمانية 1800-${GameEngine.endYear}؛ اللاعب هو السلطان نفسه. '
      'اكتب جولة نصف سنوية: briefing ثم ثلاثة قرارات (internal وeconomy وforeign) لكل منها ثلاثة خيارات مختلفة جوهريا، ولكل خيار ثمن وخطر.',
    )
    ..writeln('القواعد:')
    ..writeln(
      '1) التاريخ الحقيقي هو الخلفية، والتاريخ البديل يبنى على قرارات اللاعب ونتائجها فقط (آخر قراراته وتقرير الميزانية والأحداث أدناه). لا مفارقات تاريخية، وللتنفيذ وقت ولكل قرار ردود فعل.',
    )
    ..writeln(
      '2) المناخ والمؤامرات وتقارير الاستخبارات وعلاقات الدول تحسبها اللعبة بأرقام: استثمرها سرديا ولا تخترع أرقامها. تقارير الاستخبارات قد تكون كاذبة فعاملها كشائعات.',
    )
    ..writeln(
      '3) حدود الأرقام (يخفض الزائد تلقائيا): cost حتى ${_n(revenue * Calibrator.maxCostShare)}، loan حتى ${_n(revenue * Calibrator.maxLoanShare * DiplomacyRules.creditFactor(s))}، '
      'line_changes حتى ${Calibrator.maxLineChanges} بنود وكل تغيير سنوي بين ±${_n(revenue * Calibrator.maxLineShare)} (مفاتيح: ${[...revenueLines, ...spendingLines].map((l) => '${l.key}=${l.label}').join('، ')}؛ الإيراد الجديد يتأخر نصف سنة على الأقل). '
      'now بين ±${Calibrator.maxNow}، later بين ±${Calibrator.maxLater}، delay من 0 إلى ${Calibrator.maxDelay} أنصاف سنوات، ومجموع المكاسب الموجبة في الخيار ≤ ${Calibrator.maxTotalGain}.',
    )
    ..writeln(
      '4) rel: تغيير علاقة دول (${countryDefs.map((c) => '${c.key}=${c.name}').join('، ')}) حتى ±${Calibrator.maxRelation}. '
      'pow: تغيير رضا قوى (${powerDefs.map((p) => '${p.key}=${p.name}').join('، ')}) حتى ±${Calibrator.maxPowerMood}. '
      'اذكر فقط ما يتأثر فعلا (حتى ${Calibrator.maxMapKeys} لكل منهما). dissolve: مفتاح قوة يقرر الخيار نفسه حلها نهائيا (نادر). '
      'war: دولة يعلن الخيار الحرب عليها (أو تعلنها علينا). peace: دولة يطلب الخيار الصلح معها. '
      'project: مفتاح مشروع قومي يبدأه الخيار (واحد فقط في كل وقت، من: ${projectCatalog.map((d) => '${d.key}=${d.name} من ${d.fromYear}').join('، ')}).',
    )
    ..writeln(
      '4أ) الحروب والمشاريع والولايات والديون تحسبها اللعبة بالأرقام (نقاط الحرب، أقساط المشروع، الانفصال، الفوائد): لا تقرر نتيجة معركة ولا تخترع أرقامها، اكتب سردها وقراراتها فقط.',
    )
    ..writeln(
      '5) العربية المبسطة الموجزة: scene≤60 كلمة، dilemma≤30، text≤28، result≤35، reaction≤22، note (الأساس التاريخي)≤18، briefing≤90.',
    )
    ..writeln(
      '6) world: حدّث القوائم كاملة وقصيرة (≤${WorldMemory.maxItems} عناصر لكل قائمة و≤12 كلمة للعنصر): الحروب الجارية، التحالفات والمعاهدات، الإصلاحات الجارية، الوعود. chronicle ملاحظة ≤40 كلمة لما لا يتسع فيها.',
    )
    ..writeln('الرد: كائن JSON واحد فقط، بلا نص خارجه ولا أسوار كود، بهذا الشكل (الحقول الاختيارية تحذف إن كانت فارغة):')
    ..writeln(_schemaExample)
    ..writeln();

  // ───── القسم المتغير ─────
  buf
    ..writeln('الفترة: ${GameEngine.periodLabel(s.round)} (الجولة ${s.round + 1} من ${GameEngine.totalRounds}).')
    ..writeln(
      'الحالة (قروش، 1 قرش = 40 بارة): خزينة ${_n(s.treasury)}، دين ${_n(s.debt)} (${ratio.toStringAsFixed(2)}× الإيراد السنوي).',
    )
    ..writeln(
      'المؤشرات/100: شرعية ${s.legitimacy}، استقرار ${s.stability} '
      '[${StabilityState.keys.map((k) => '${StabilityState.labels[k]} ${s.stab[k].round()}').join('، ')}]، '
      'جيش ${s.army} (≈${_n(s.army * 4000)} جندي)، مكانة دولية ${s.foreign}، تعليم ${s.education}.',
    )
    ..writeln('إيراد سنوي ${_n(revenue)}: ${_lines(revenueLines, s.budget)}')
    ..writeln('نفقات سنوية ${_n(s.budget.totalSpending)}: ${_lines(spendingLines, s.budget)}')
    ..writeln(
      'اقتصاد: حبوب ${_n(s.econ.grain)} (100 معتاد)، تضخم ${s.econ.inflation.toStringAsFixed(1)}%، فساد ${_n(s.econ.corruption)}، '
      'أنصاف سنوات عجز متتالية ${s.econ.deficitStreak}. الولايات (مزاج/ميل للانفصال): '
      '${s.econ.provinces.values.map((p) => p.isLost ? '${p.name} مفقودة' : '${p.name} ${_n(p.mood)}/${_n(p.autonomy)}${p.status == 'autonomous' ? ' شبه مستقلة' : ''}').join('، ')}.',
    )
    ..writeln(
      'سكان ${s.demog.population.toStringAsFixed(1)} مليون، قراءة وكتابة ${s.demog.literacy.toStringAsFixed(1)}%، مدارس ابتدائية ${_n(s.demog.schools)}.',
    );

  final powers = s.powers.values.map((p) {
    if (p.dissolved) return '${p.name} (محلولة)';
    return '${p.name} نفوذ ${_n(p.influence)} رضا ${_n(p.satisfaction)} خطر ${_n(p.danger)}';
  }).join('؛ ');
  buf.writeln('قوى الدولة: $powers.');

  final countries = s.countries.values.map((c) {
    final tags = <String>[
      if (c.embassy) 'سفارة',
      if (c.spy > 0) 'تجسس ${c.spy}',
    ];
    final eco = ForeignRules.econRatio(s, c).toStringAsFixed(1);
    final mil = ForeignRules.milRatio(s, c).toStringAsFixed(1);
    return '${c.name} ${_n(c.relation)}${tags.isEmpty ? '' : ' (${tags.join('، ')})'} اقتصاد $eco× جيش $mil×';
  }).join('؛ ');
  buf.writeln('الدول (علاقة/100، وقوتها نسبة إلى قوتنا): $countries.');
  if (s.wars.isNotEmpty) {
    buf.writeln(
      'حروب جارية: ${s.wars.map((w) => '${w.enemyName} (${WarRules.describe(w)}، نقاط ${_n(w.score)}، منذ ${w.halves} أنصاف، ${w.byUs ? 'بدأناها' : 'بدأوها'})').join('؛ ')}.',
    );
  }
  if (s.domesticSpy > 0) buf.writeln('الاستخبارات الداخلية: مستوى ${s.domesticSpy}.');

  final prj = s.project;
  if (prj != null) {
    final d = projectDef(prj.key);
    buf.writeln(
      'مشروع قومي جار: ${d?.name ?? prj.key} اكتمل ${(prj.progress * 100).round()}% (باقٍ ${prj.remaining} أنصاف${prj.stalled > 0 ? '، متعثر للتمويل' : ''}).',
    );
  }
  if (s.completed.isNotEmpty) {
    buf.writeln('مشاريع منجزة: ${s.completed.map((k) => projectDef(k)?.name ?? k).join('، ')}.');
  }
  if (s.foreignDebt > 0 || s.defaultRound >= 0) {
    buf.writeln(
      'الدين الخارجي ${_n(s.foreignDebt)} من ${_n(s.debt)}، تصنيف ائتماني ${_n(DebtRules.creditRating(s))}/100'
      '${s.defaultRound >= 0 ? '، سبق العجز عن السداد' : ''}${s.dadActive ? '، إدارة الديون العامة تحصّل جزءا من الإيراد' : ''}.',
    );
  }
  if (s.projects.isNotEmpty) {
    buf.writeln(
      'مشاريع على القوى: ${s.projects.map((p) => '${PowerProject.kindLabels[p.kind]} ${powerDef(p.power)?.name ?? p.power} (${p.remaining} أنصاف)').join('؛ ')}.',
    );
  }

  final rumors = s.intel.where((r) => !r.revealed).toList();
  if (rumors.isNotEmpty) {
    buf.writeln('تقارير استخبارات غير مؤكدة: ${rumors.map((r) => '${r.claim} (${r.reliability}%)').join('؛ ')}.');
  }

  if (s.pending.isNotEmpty) {
    buf.writeln(
      'آثار مؤجلة قادمة: ${s.pending.map((p) => '${GameEngine.periodLabel(p.dueRound)}: ${_clip(p.source, 60)}').join('؛ ')}.',
    );
  }

  if (!s.world.isEmpty) {
    String l(String label, List<String> xs) => xs.isEmpty ? '' : '$label: ${xs.join('؛ ')}. ';
    buf.writeln(
      'ذاكرة العالم: ${l('حروب', s.world.wars)}${l('تحالفات', s.world.alliances)}${l('إصلاحات', s.world.reforms)}${l('وعود', s.world.promises)}'
          .trim(),
    );
  }
  if (s.chronicle.trim().isNotEmpty) buf.writeln('ملاحظة: ${_clip(s.chronicle.trim(), Calibrator.maxChronicle)}');
  if (s.lastReport.trim().isNotEmpty) buf.writeln(s.lastReport.trim());

  // قرارات اللاعب: هي ما تبني عليه الجولة التالية
  if (s.history.isEmpty) {
    buf.writeln('لا قرارات سابقة: هذه بداية الحملة، ابدأ من الوضع الحقيقي مطلع 1800.');
  } else {
    final from = s.history.length > _historyEntries ? s.history.length - _historyEntries : 0;
    final recent = s.history.sublist(from);
    buf.writeln('قرارات اللاعب الأخيرة (الأحدث آخرا):');
    for (var i = 0; i < recent.length; i++) {
      final h = recent[i];
      final detailed = i >= recent.length - _detailedEntries;
      buf.writeln(
        '- ${GameEngine.periodLabel(h.round)} | ${h.category} | ${h.title}: ${_clip(h.choice, detailed ? 170 : 80)}',
      );
    }
  }

  final anchors = anchorsFor(year);
  if (anchors.isNotEmpty) buf.writeln('مرجع التاريخ القريب (قد ينحرف بقرارات اللاعب): ${anchors.join(' ')}');

  if (problem != null && problem.trim().isNotEmpty) {
    buf.writeln('تنبيه: ردك السابق رُفض لأن: ${problem.trim()} أعد JSON كاملا وصحيحا.');
  } else {
    buf.writeln('أعد JSON فقط.');
  }
  return buf.toString();
}

const String _schemaExample =
    '{"headline":"عنوان","briefing":"ملخص","chronicle":"ملاحظة","world":{"wars":[],"alliances":[],"reforms":[],"promises":[]},'
    '"decisions":[{"category":"internal","title":"..","place":"..","scene":"..","dilemma":"..","options":[{"text":"..","result":"..","reaction":"..","note":"..",'
    '"cost":0,"loan":0,"now":{"legitimacy":0,"stability":0,"army":0,"foreign":0,"education":0},"later":{"legitimacy":0,"stability":0,"army":0,"foreign":0,"education":0},'
    '"delay":0,"line_changes":[{"line":"army","delta":0}],"rel":{"britain":0},"pow":{"ulema":0},"dissolve":"","war":"","peace":"","project":""}]}]}';
