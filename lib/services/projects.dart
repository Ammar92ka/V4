import '../data/projects_catalog.dart';
import '../models/game_state.dart';
import '../models/systems.dart';
import 'sim_common.dart';

/// نتيجة تمويل نصف سنة من المشروع القومي.
class ProjectStep {
  final double spent;
  final List<String> notes;
  const ProjectStep(this.spent, this.notes);
}

/// المشاريع القومية: واحد في كل وقت، تمويل بأقساط نصف سنوية، وفوائد تظهر عند الاكتمال.
class ProjectRules {
  ProjectRules._();

  /// أقصى زيادة في التكلفة عند اختيار أقصر مدة.
  static const double rushPremium = 0.25;

  static bool has(GameState s, String key) => s.completed.contains(key);

  /// هل أنجزنا مشروعا له هذه الميزة؟
  static bool hasPerk(GameState s, String perk) =>
      s.completed.any((k) => projectDef(k)?.perk == perk);

  /// عدد المشاريع المنجزة التي لها هذه الميزة.
  static int perkCount(GameState s, String perk) =>
      s.completed.where((k) => projectDef(k)?.perk == perk).length;

  static bool isAvailable(GameState s, ProjectDef d) =>
      yearOfRound(s.round) >= d.fromYear && !s.completed.contains(d.key);

  static List<ProjectDef> available(GameState s) => [
    for (final d in projectCatalog)
      if (isAvailable(s, d)) d,
  ];

  static int clampHalves(ProjectDef d, int halves) =>
      halves.clamp(d.minHalves, d.maxHalves).toInt();

  /// التكلفة الكلية لمدة معينة: الأقصر أغلى بحتى 25%.
  static double totalCost(GameState s, ProjectDef d, int halves) {
    final h = clampHalves(d, halves);
    final span = d.maxHalves - d.minHalves;
    final premium = span <= 0 ? 1.0 : 1 + rushPremium * (d.maxHalves - h) / span;
    return (s.budget.totalRevenue * d.cost * premium).roundToDouble();
  }

  static double installment(GameState s, ProjectDef d, int halves) =>
      (totalCost(s, d, halves) / clampHalves(d, halves)).roundToDouble();

  /// يبدأ مشروعا. من الديوان يستهلك إجراء ويشترط قسطا أول في الخزينة؛
  /// ومن قرار ذكاء اصطناعي ([viaDecision]) لا يشترط ذلك.
  static CourtResult start(GameState s, String key, int halves, {bool viaDecision = false}) {
    final d = projectDef(key);
    if (d == null) return const CourtResult(false, 'مشروع غير معروف');
    if (s.project != null) {
      return const CourtResult(false, 'لديك مشروع جار؛ أتمه أو ألغه قبل بدء غيره');
    }
    if (s.completed.contains(key)) return CourtResult(false, '${d.name} منجز أصلا');
    if (yearOfRound(s.round) < d.fromYear) {
      return CourtResult(false, '${d.name} غير ممكن قبل ${d.fromYear}');
    }
    final h = clampHalves(d, halves);
    final inst = installment(s, d, h);
    if (!viaDecision) {
      if (s.courtActions <= 0) {
        return const CourtResult(false, 'استنفدت إجراءات الديوان لنصف السنة هذا');
      }
      if (s.treasury < inst) {
        return const CourtResult(false, 'الخزينة لا تكفي للقسط الأول');
      }
      s.courtActions -= 1;
      s.courtLog.add('بدء مشروع ${d.name}');
    }
    s.project = ActiveProject(key, h, inst, s.round);
    return CourtResult(true, 'بدأ مشروع ${d.name}: $h أنصاف سنوات بقسط نصف سنوي');
  }

  /// إلغاء المشروع الجاري: ما أنفق ضاع.
  static CourtResult cancel(GameState s) {
    final p = s.project;
    if (p == null) return const CourtResult(false, 'لا مشروع جار');
    final d = projectDef(p.key);
    s.project = null;
    s.courtLog.add('إلغاء مشروع ${d?.name ?? p.key}');
    return CourtResult(true, 'أُلغي المشروع وضاع ما أُنفق عليه');
  }

  /// يدفع قسط نصف السنة إن وجد في الخزينة، وإلا يتعثر المشروع. يعيد ما دفع وملاحظات.
  static ProjectStep fund(GameState s) {
    final p = s.project;
    if (p == null) return const ProjectStep(0, []);
    final d = projectDef(p.key);
    if (d == null) {
      s.project = null;
      return const ProjectStep(0, []);
    }
    final notes = <String>[];
    var spent = 0.0;
    if (s.treasury >= p.installment) {
      s.treasury -= p.installment;
      spent = p.installment;
      p.funded += 1;
      p.stalled = 0;
      if (p.funded >= p.halves) notes.add(_complete(s, d));
    } else {
      p.stalled += 1;
      notes.add('تعثر مشروع ${d.name} لنقص التمويل (نصف سنة رقم ${p.stalled})');
    }
    return ProjectStep(spent, notes);
  }

  static String _complete(GameState s, ProjectDef d) {
    final rev = s.budget.totalRevenue;
    d.lines.forEach((line, pct) => s.budget.change(line, rev * pct));
    if (d.upkeep > 0) s.budget.change(d.upkeepLine, rev * d.upkeep);

    final e = d.effects;
    s.legitimacy = (s.legitimacy + e.legitimacy).clamp(0, 100).toInt();
    s.army = (s.army + e.army).clamp(0, 100).toInt();
    s.foreign = (s.foreign + e.foreign).clamp(0, 100).toInt();
    s.education = (s.education + e.education).clamp(0, 100).toInt();
    if (e.stability != 0) s.stab.shiftAll(e.stability.toDouble());

    final econ = s.econ;
    if (d.mood != 0) {
      for (final p in econ.provinces.values) {
        if (!p.isLost) p.mood = clampD(p.mood + d.mood, 0, 100);
      }
    }
    d.provinceMood.forEach((k, v) {
      final p = econ.provinces[k];
      if (p != null && !p.isLost) p.mood = clampD(p.mood + v, 0, 100);
    });
    econ.corruption = clampD(econ.corruption + d.corruption, 5, 95);
    econ.inflation = clampD(econ.inflation + d.inflation, 1, 12);
    s.demog.schools = clampD(s.demog.schools + d.schools, 0, 1e7);
    s.demog.literacy = clampD(s.demog.literacy + d.literacy, 1, 80);
    d.powers.forEach((k, v) {
      final p = s.powers[k];
      if (p != null && !p.dissolved) p.satisfaction = clampD(p.satisfaction + v, 0, 100);
    });

    s.completed.add(d.key);
    s.project = null;
    return 'اكتمل مشروع ${d.name}: ${d.benefits}';
  }
}
