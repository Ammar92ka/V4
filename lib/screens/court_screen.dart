import 'package:flutter/material.dart';

import '../data/projects_catalog.dart';
import '../models/game_state.dart';
import '../models/systems.dart';
import '../services/debt.dart';
import '../services/diplomacy.dart';
import '../services/foreign.dart';
import '../services/powers.dart';
import '../services/projects.dart';
import '../services/provinces.dart';
import '../services/save_service.dart';
import '../services/sim_common.dart';
import '../services/wars.dart';
import '../ui/format.dart';
import '../ui/theme.dart';

/// الديوان: كل ما يديره السلطان بنفسه بين الجولات (استقرار وقوى وسفارات وجواسيس واقتصاد).
/// الإجراءات تنفذ فورا وتحفظ، وأثرها يظهر في تقرير نصف السنة ويصل إلى الذكاء الاصطناعي.
class CourtScreen extends StatefulWidget {
  const CourtScreen({super.key, required this.state, required this.save});

  final GameState state;
  final SaveService save;

  @override
  State<CourtScreen> createState() => _CourtScreenState();
}

class _CourtScreenState extends State<CourtScreen> {
  GameState get s => widget.state;

  /// المدة المختارة لكل مشروع قبل بدئه (بأنصاف السنة).
  final Map<String, int> _durations = {};

  /// ينفذ إجراء، ويعرض نتيجته، ويحفظ الحالة.
  Future<void> _run(CourtResult Function() action) async {
    final result = action();
    setState(() {});
    if (result.message.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result.message)));
    }
    await widget.save.saveState(s);
  }

  Future<bool> _confirm(String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text, style: const TextStyle(height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نفّذ')),
        ],
      ),
    );
    return ok == true;
  }

  // ───────────── عناصر مشتركة ─────────────

  Widget _card({required Widget child, Color? border}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border ?? AppColors.cardBorder),
      ),
      child: child,
    );
  }

  Widget _bar(String label, double value, {bool invert = false, String? text}) {
    final v = value.clamp(0.0, 100.0).toDouble();
    final bad = invert ? v >= 60 : v <= 25;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: v / 100,
                minHeight: 7,
                color: bad ? AppColors.bad : AppColors.gold,
                backgroundColor: AppColors.cardBorder,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              text ?? v.round().toString(),
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 16)),
  );

  Widget _hint(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(t, style: const TextStyle(color: AppColors.muted, height: 1.6, fontSize: 13)),
  );

  String _cost(double share) => '${formatMoney(costShare(s, share))} قرش';

  bool get _noActions => s.courtActions <= 0;

  // ───────────── الاستقرار والقوى ─────────────

  Widget _stabilityTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _hint(
          'الاستقرار الكلي متوسط ستة أبعاد. إذا هبطت ثلاثة أبعاد إلى الحضيض انهار النظام ولو بدا المتوسط مقبولا. '
          'لديك ${s.courtActions} إجراء في نصف السنة هذا (الترضية والمشاريع والحل والهدايا والمعاهدات).',
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title('الاستقرار الكلي ${s.stability} / 100'),
              for (final k in StabilityState.keys)
                _bar(StabilityState.labels[k] ?? k, s.stab[k]),
            ],
          ),
        ),
        for (final p in s.powers.values) _powerCard(p),
      ],
    );
  }

  Widget _powerCard(PowerState p) {
    PowerProject? project;
    for (final pr in s.projects) {
      if (pr.power == p.key) project = pr;
    }
    if (p.dissolved) {
      return _card(
        child: Text('${p.name}: حُلت نهائيا.', style: const TextStyle(color: AppColors.muted)),
      );
    }
    final danger = p.danger;
    final busy = project != null;
    return _card(
      border: danger >= 60 ? AppColors.bad : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              if (danger >= 60) const Icon(Icons.warning_amber, color: AppColors.bad, size: 20),
            ],
          ),
          Text(p.def.about, style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5)),
          const SizedBox(height: 6),
          _bar('النفوذ', p.influence),
          _bar('الرضا', p.satisfaction),
          _bar('الخطر', danger, invert: true),
          if (project != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'مشروع جار: ${PowerProject.kindLabels[project.kind]} (باقٍ ${project.remaining} من أنصاف السنة)',
                style: const TextStyle(color: AppColors.gold, fontSize: 13),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _noActions ? null : () => _run(() => PowerRules.appease(s, p.key)),
                child: Text('ترضية ${_cost(PowerRules.appeaseShare)}'),
              ),
              OutlinedButton(
                onPressed: (_noActions || busy)
                    ? null
                    : () => _run(() => PowerRules.startProject(s, p.key, 'reform')),
                child: Text('إصلاح ${_cost(PowerRules.reformShare)}'),
              ),
              OutlinedButton(
                onPressed: (_noActions || busy)
                    ? null
                    : () => _run(() => PowerRules.startProject(s, p.key, 'contain')),
                child: Text('احتواء ${_cost(PowerRules.containShare)}'),
              ),
              OutlinedButton(
                onPressed: (_noActions || busy)
                    ? null
                    : () => _run(() => PowerRules.startProject(s, p.key, 'merge')),
                child: Text('دمج ${_cost(PowerRules.mergeShare)}'),
              ),
              OutlinedButton(
                onPressed: _noActions
                    ? null
                    : () async {
                        final risky = danger > 70;
                        final ok = await _confirm(
                          risky
                              ? 'خطر ${p.name} مرتفع: قد ترتد محاولة حلها بتمرد وخسارة هيبة (${PowerRules.dissolveRisk(p)}). هل تحل ${p.name}؟'
                              : 'هل تحل ${p.name} نهائيا؟',
                        );
                        if (ok) await _run(() => PowerRules.dissolve(s, p.key));
                      },
                child: Text('حل ${_cost(PowerRules.dissolveShare)}'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────── الدبلوماسية والسفارات ─────────────

  Widget _diplomacyTab() {
    final credit = DiplomacyRules.creditFactor(s);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _hint(
          'علاقات الدائنين (بريطانيا وفرنسا والنمسا) تحدد سقف قروضك: المعامل الآن ${credit.toStringAsFixed(2)}. '
          'السفارة تحفظ العلاقة وتفتح لك أعين التجسس، وكلفتها السنوية تضاف إلى بند الإدارة.',
        ),
        if (s.wars.isNotEmpty) ...[
          _title('حروب جارية'),
          for (final w in s.wars) _warCard(w),
        ],
        for (final c in s.countries.values) _countryCard(c),
      ],
    );
  }

  Widget _warCard(War w) {
    final c = s.countries[w.enemy];
    final our = WarRules.ourPower(s);
    final enemy = c == null ? 0.0 : WarRules.enemyPower(c);
    return _card(
      border: AppColors.bad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الحرب مع ${w.enemyName} (${w.byUs ? 'بدأناها' : 'بدأوها'})',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _bar('الموقف', (w.score + 100) / 2, text: '${w.score.round()}'),
          Text(
            '${WarRules.describe(w)} • منذ ${w.halves} من أنصاف السنة • قوتنا ${our.round()} مقابل ${enemy.round()} • كلفة النصف ${formatMoney(s.budget.totalRevenue * 0.04)} قرش وأكثر',
            style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _noActions
                ? null
                : () async {
                    final ok = await _confirm(
                      'شروط الصلح تتبع موقفك الآن (${WarRules.describe(w)}): قد تدفع تعويضا أو تتنازل عن أرض إن كنت خاسرا. هل تطلب الصلح؟',
                    );
                    if (ok) await _run(() => WarRules.seekPeace(s, w.enemy));
                  },
            child: Text('طلب الصلح ${_cost(WarRules.peaceShare)}'),
          ),
        ],
      ),
    );
  }

  Widget _countryCard(CountryState c) {
    final econR = ForeignRules.econRatio(s, c);
    final milR = ForeignRules.milRatio(s, c);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              Text(
                DiplomacyRules.relationLabel(c.relation),
                style: TextStyle(color: c.relation < 25 ? AppColors.bad : AppColors.gold),
              ),
            ],
          ),
          _bar('العلاقة', c.relation),
          _bar('اقتصاده', econR / 3 * 100, text: '${econR.toStringAsFixed(1)}×'),
          _bar('جيشه', milR / 3 * 100, invert: true, text: '${milR.toStringAsFixed(1)}×'),
          Text(
            '${ForeignRules.strengthLabel(milR)} عسكريا، و${ForeignRules.strengthLabel(econR)} اقتصاديا (بالنسبة لنا).',
            style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5),
          ),
          Text(
            c.embassy ? 'لنا سفارة دائمة.' : 'لا سفارة دائمة.',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (c.embassy)
                OutlinedButton(
                  onPressed: () => _run(() => DiplomacyRules.closeEmbassy(s, c.key)),
                  child: const Text('إغلاق السفارة'),
                )
              else
                FilledButton.tonal(
                  onPressed: () => _run(() => DiplomacyRules.openEmbassy(s, c.key)),
                  child: Text('افتتاح سفارة ${_cost(DiplomacyRules.embassyOpenShare)}'),
                ),
              OutlinedButton(
                onPressed: _noActions ? null : () => _run(() => DiplomacyRules.gift(s, c.key)),
                child: Text('هدايا ${_cost(DiplomacyRules.giftShare)}'),
              ),
              OutlinedButton(
                onPressed: _noActions ? null : () => _run(() => DiplomacyRules.tradeTreaty(s, c.key)),
                child: Text('معاهدة تجارية ${_cost(DiplomacyRules.treatyShare)}'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────── الاستخبارات ─────────────

  static const List<ButtonSegment<int>> _levels = [
    ButtonSegment<int>(value: 0, label: Text('لا')),
    ButtonSegment<int>(value: 1, label: Text('محدودة')),
    ButtonSegment<int>(value: 2, label: Text('واسعة')),
  ];

  Widget _spiesTab() {
    final reports = s.intel.reversed.toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _hint(
          'الجواسيس يجلبون تقارير بدرجة موثوقية، وقد يكذب التقرير. تنكشف حقيقته بعد نصف سنة فتعرف من تثق به. '
          'تجنيد الشبكة يكلف مرة واحدة، وتشغيلها يضاف إلى بند الإدارة سنويا.',
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title('الاستخبارات الداخلية'),
              const Text(
                'تكشف مؤامرات القوى قبل وقوعها وتقدم تقارير عن أخطرها.',
                style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: _levels,
                selected: {s.domesticSpy},
                onSelectionChanged: (v) => _run(() => DiplomacyRules.setDomesticSpy(s, v.first)),
              ),
            ],
          ),
        ),
        for (final c in s.countries.values)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title('التجسس على ${c.name}'),
                Text(
                  'جودة المعلومات: ${c.intelQuality} من 3 (السفارة تضيف درجة).',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: _levels,
                  selected: {c.spy},
                  onSelectionChanged: (v) => _run(() => DiplomacyRules.setSpyLevel(s, c.key, v.first)),
                ),
              ],
            ),
          ),
        _title('التقارير'),
        if (reports.isEmpty)
          const Text('لا تقارير بعد.', style: TextStyle(color: AppColors.muted))
        else
          for (final r in reports) _reportTile(r),
      ],
    );
  }

  Widget _reportTile(SpyReport r) {
    final String status;
    final Color color;
    if (!r.revealed) {
      status = 'غير مؤكد';
      color = AppColors.muted;
    } else if (r.truth) {
      status = 'تبين أنه صحيح';
      color = AppColors.good;
    } else {
      status = 'تبين أنه كاذب';
      color = AppColors.bad;
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.claim, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 4),
          Text(
            'الموثوقية ${r.reliability}% • $status',
            style: TextStyle(color: color, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ───────────── الاقتصاد العميق ─────────────

  Widget _economyTab() {
    final e = s.econ;
    final d = s.demog;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _hint(
          'هذه أرقام تحسبها اللعبة بقواعد ثابتة، وتتأثر بها الجباية والاستقرار. العجز الطويل يغذي التضخم، '
          'ورفع الضرائب يغضب الولايات، والجفاف يرفع أسعار الحبوب.',
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title('الأسعار والمال'),
              _bar('الحبوب', (e.grain / 2.6).clamp(0.0, 100.0).toDouble(), invert: true, text: e.grain.round().toString()),
              _bar('التضخم', (e.inflation * 10).clamp(0.0, 100.0).toDouble(), invert: true, text: '${e.inflation.toStringAsFixed(1)}%'),
              _bar('الفساد', e.corruption, invert: true),
              const SizedBox(height: 4),
              Text(
                'أنصاف سنوات عجز متتالية: ${e.deficitStreak}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              Text(
                'مضاعف الجباية من الولايات والفساد: ${e.revenueMultiplier.toStringAsFixed(3)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        _debtCard(),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title('السكان والتعليم (تقديري)'),
              Text('السكان: ${d.population.toStringAsFixed(1)} مليون'),
              const SizedBox(height: 4),
              Text('القراءة والكتابة: ${d.literacy.toStringAsFixed(1)}%'),
              const SizedBox(height: 4),
              Text('المدارس الابتدائية: ${formatNumber(d.schools)}'),
              const SizedBox(height: 4),
              Text('الجنود: نحو ${formatNumber(s.army * 4000)}'),
            ],
          ),
        ),
      ],
    );
  }


  // ───────────── الدين ─────────────

  Widget _debtCard() {
    final rev = s.budget.totalRevenue;
    final rating = DebtRules.creditRating(s);
    final status = s.dadActive
        ? 'إدارة الديون العامة تحصّل ${(DebtRules.dadShare * 100).round()}% من الإيراد للدائنين.'
        : (DebtRules.inMoratorium(s)
              ? 'الفوائد الخارجية معلقة بعد إعلان العجز عن السداد.'
              : (s.defaultRound >= 0 ? 'سبق أن عجزت الدولة عن السداد، والدائنون يذكرون ذلك.' : ''));
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('الدين والتصنيف الائتماني'),
          Text('الدين الداخلي: ${formatMoney(DebtRules.internalDebt(s))} قرش (فائدة 12% سنويا)'),
          const SizedBox(height: 4),
          Text(
            'الدين الخارجي: ${formatMoney(s.foreignDebt)} قرش'
            '${s.foreignDebt > 0 ? ' (فائدة ${(DebtRules.foreignRate(s) * 100).toStringAsFixed(1)}% سنويا)' : ''}',
          ),
          const SizedBox(height: 4),
          Text('الدين الكلي ${(s.debt / (rev <= 0 ? 1 : rev)).toStringAsFixed(2)}× الإيراد السنوي'),
          const SizedBox(height: 6),
          _bar('التصنيف', rating),
          if (status.isNotEmpty)
            Text(status, style: const TextStyle(color: AppColors.gold, fontSize: 13, height: 1.5)),
          const Text(
            'القروض الأجنبية تبدأ من 1854، وإن تراكم الدين الأجنبي مع اقتراض طارئ متتال عجزت الدولة عن السداد.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ───────────── الولايات ─────────────

  Widget _provincesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _hint(
          'كل ولاية لها مزاج وميل إلى الانفصال. إذا بلغ الحكم الذاتي 70 صارت شبه مستقلة (تدفع 40% من إيرادها)، وعند 95 قد تنفصل. '
          'الجيش القوي يقمع، والرضا والشرعية العاليان يبطئان الانفصال. إذا هبط وزن الولايات الفعالة دون 40% تفككت الإمبراطورية '
          '(الآن ${(s.econ.activeWeight * 100).round()}%).',
        ),
        for (final p in s.econ.provinces.values) _provinceCard(p),
      ],
    );
  }

  Widget _provinceCard(ProvinceState p) {
    if (p.isLost) {
      return _card(
        child: Text('${p.name}: مفقودة (${(p.def.weight * 100).round()}% من قاعدة الإيراد).', style: const TextStyle(color: AppColors.muted)),
      );
    }
    final risky = p.autonomy >= 70;
    return _card(
      border: risky ? AppColors.bad : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              Text(
                ProvinceState.statusLabels[p.status] ?? p.status,
                style: TextStyle(color: risky ? AppColors.bad : AppColors.gold),
              ),
            ],
          ),
          Text(
            'وزنها في الإيراد ${(p.def.weight * 100).round()}%',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          _bar('المزاج', p.mood),
          _bar('الانفصال', p.autonomy, invert: true),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _noActions ? null : () => _run(() => ProvinceRules.suppress(s, p.key)),
                child: Text('قمع ${_cost(ProvinceRules.suppressShare)}'),
              ),
              OutlinedButton(
                onPressed: _noActions ? null : () => _run(() => ProvinceRules.privileges(s, p.key)),
                child: Text('امتيازات ${_cost(ProvinceRules.privilegesShare)}'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────── المشاريع القومية ─────────────

  Widget _projectsTab() {
    final active = s.project;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _hint(
          'مشروع واحد فقط في كل وقت، يمول بقسط من الخزينة كل نصف سنة. قصّر المدة يغلو عليك حتى 25%. '
          'الفوائد تظهر عند الاكتمال، وللمشروع صيانة سنوية دائمة. إذا نقص المال تعثر المشروع ولم يتقدم. '
          'يستهلك البدء إجراء من الديوان.',
        ),
        if (active != null) _activeProjectCard(active),
        if (s.completed.isNotEmpty)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title('مشاريع منجزة'),
                for (final k in s.completed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('✓ ${projectDef(k)?.name ?? k}'),
                  ),
              ],
            ),
          ),
        _title('المشاريع المتاحة'),
        for (final d in projectCatalog) _catalogCard(d),
      ],
    );
  }

  Widget _activeProjectCard(ActiveProject p) {
    final d = projectDef(p.key);
    return _card(
      border: AppColors.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('الجاري: ${d?.name ?? p.key}'),
          _bar('الاكتمال', p.progress * 100, text: '${(p.progress * 100).round()}%'),
          Text(
            'باقٍ ${p.remaining} من ${p.halves} أنصاف سنة • القسط ${formatMoney(p.installment)} قرش'
            '${p.stalled > 0 ? ' • متعثر لنقص التمويل' : ''}',
            style: TextStyle(color: p.stalled > 0 ? AppColors.bad : AppColors.muted, fontSize: 13, height: 1.5),
          ),
          if (d != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('عند الاكتمال: ${d.benefits}', style: const TextStyle(fontSize: 13, height: 1.5)),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              final ok = await _confirm('إلغاء المشروع يضيع كل ما أنفق عليه. هل تلغيه؟');
              if (ok) await _run(() => ProjectRules.cancel(s));
            },
            child: const Text('إلغاء المشروع'),
          ),
        ],
      ),
    );
  }

  Widget _catalogCard(ProjectDef d) {
    final done = s.completed.contains(d.key);
    final open = yearOfRound(s.round) >= d.fromYear;
    final isActive = s.project?.key == d.key;
    final halves = _durations[d.key] ?? ((d.minHalves + d.maxHalves) ~/ 2);
    final total = ProjectRules.totalCost(s, d, halves);
    final inst = ProjectRules.installment(s, d, halves);
    final canStart = !done && open && s.project == null && !_noActions && s.treasury >= inst;
    if (done) return const SizedBox.shrink();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Text(d.about, style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5)),
          const SizedBox(height: 4),
          Text('الفوائد: ${d.benefits}', style: const TextStyle(fontSize: 13, height: 1.5)),
          if (!open)
            Text('متاح من سنة ${d.fromYear}', style: const TextStyle(color: AppColors.bad, fontSize: 13))
          else if (!isActive) ...[
            const SizedBox(height: 6),
            Text('المدة: $halves من أنصاف السنة (${(halves / 2).toStringAsFixed(1)} سنة)'),
            Slider(
              value: halves.toDouble(),
              min: d.minHalves.toDouble(),
              max: d.maxHalves.toDouble(),
              divisions: d.maxHalves - d.minHalves,
              onChanged: (v) => setState(() => _durations[d.key] = v.round()),
            ),
            Text(
              'الكلفة الكلية ${formatMoney(total)} قرش، بقسط ${formatMoney(inst)} كل نصف سنة',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: canStart ? () => _run(() => ProjectRules.start(s, d.key, halves)) : null,
              child: const Text('بدء المشروع'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text('الديوان • الإجراءات ${s.courtActions}'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'الاستقرار والقوى'),
              Tab(text: 'الدبلوماسية والحروب'),
              Tab(text: 'الاستخبارات'),
              Tab(text: 'الاقتصاد والدين'),
              Tab(text: 'الولايات'),
              Tab(text: 'المشاريع'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _stabilityTab(),
              _diplomacyTab(),
              _spiesTab(),
              _economyTab(),
              _provincesTab(),
              _projectsTab(),
            ],
          ),
        ),
      ),
    );
  }
}
