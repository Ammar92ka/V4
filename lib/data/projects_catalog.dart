import '../models/round_plan.dart';

/// مشروع قومي من كتالوج اللعبة. الأرقام ثابتة في الكود (لا تستهلك توكنات)،
/// والذكاء الاصطناعي يستطيع اقتراح بدء مشروع بمفتاحه فقط ويكتب سرده.
///
/// التكلفة نسبة من الإيراد السنوي وقت البدء، وتزيد حتى 25% إذا اخترت أقصر مدة.
/// الفوائد تظهر عند الاكتمال (والصيانة السنوية تضاف دائما إلى بند من الميزانية).
class ProjectDef {
  final String key;
  final String name;
  final String about;

  /// متاح من هذه السنة.
  final int fromYear;

  /// التكلفة الأساسية كنسبة من الإيراد السنوي (للمدة الأطول).
  final double cost;
  final int minHalves;
  final int maxHalves;

  /// عند الاكتمال: زيادة في بنود الإيراد كنسبة من الإيراد السنوي.
  final Map<String, double> lines;

  /// عند الاكتمال: أثر فوري على المؤشرات.
  final Effects effects;

  /// صيانة سنوية دائمة (نسبة من الإيراد السنوي) على بند من النفقات.
  final String upkeepLine;
  final double upkeep;

  /// عند الاكتمال: أثر على رضا القوى.
  final Map<String, int> powers;

  /// عند الاكتمال: مدارس إضافية ونقاط في نسبة التعلم.
  final double schools;
  final double literacy;

  /// عند الاكتمال: تغيير في الفساد (سالب = تحسن) وفي التضخم السنوي.
  final double corruption;
  final double inflation;

  /// عند الاكتمال: ارتفاع في مزاج كل الولايات، أو في ولايات بعينها.
  final double mood;
  final Map<String, double> provinceMood;

  /// ميزة دائمة (انظر ProjectRules): drought, plague, credit, logistics, tech, trade.
  final String perk;

  const ProjectDef({
    required this.key,
    required this.name,
    required this.about,
    required this.fromYear,
    required this.cost,
    required this.minHalves,
    required this.maxHalves,
    this.lines = const {},
    this.effects = const Effects(),
    this.upkeepLine = 'admin',
    this.upkeep = 0,
    this.powers = const {},
    this.schools = 0,
    this.literacy = 0,
    this.corruption = 0,
    this.inflation = 0,
    this.mood = 0,
    this.provinceMood = const {},
    this.perk = '',
  });

  /// وصف مختصر للفوائد لعرضها قبل البدء.
  String get benefits {
    final parts = <String>[];
    const lineNames = {'customs': 'الجمارك', 'land': 'ضرائب الأرض', 'provinces': 'إيراد الولايات', 'other': 'إيرادات أخرى'};
    lines.forEach((k, v) => parts.add('${lineNames[k] ?? k} +${(v * 100).round()}% من الإيراد'));
    final e = effects;
    if (e.legitimacy != 0) parts.add('الشرعية ${e.legitimacy > 0 ? '+' : ''}${e.legitimacy}');
    if (e.stability != 0) parts.add('الاستقرار ${e.stability > 0 ? '+' : ''}${e.stability}');
    if (e.army != 0) parts.add('الجيش ${e.army > 0 ? '+' : ''}${e.army}');
    if (e.foreign != 0) parts.add('المكانة ${e.foreign > 0 ? '+' : ''}${e.foreign}');
    if (e.education != 0) parts.add('التعليم ${e.education > 0 ? '+' : ''}${e.education}');
    if (schools > 0) parts.add('مدارس +${schools.round()}');
    if (corruption < 0) parts.add('فساد أقل');
    if (inflation < 0) parts.add('تضخم أقل');
    if (mood > 0 || provinceMood.isNotEmpty) parts.add('رضا الولايات أعلى');
    switch (perk) {
      case 'drought':
        parts.add('يخفف خسائر الجفاف');
      case 'plague':
        parts.add('يخفف خسائر الطاعون');
      case 'credit':
        parts.add('يرفع التصنيف الائتماني');
      case 'logistics':
        parts.add('يرفع قوتنا في الحرب');
      case 'tech':
        parts.add('جيش أحدث في الحرب');
    }
    return parts.join('، ');
  }
}

const List<ProjectDef> projectCatalog = [
  ProjectDef(
    key: 'roads',
    name: 'شبكة طرق ومعابر',
    about: 'طرق ممهدة وجسور بين الولايات تسهل التجارة والجباية وحركة الجند.',
    fromYear: 1800,
    cost: 0.50,
    minHalves: 6,
    maxHalves: 14,
    lines: {'customs': 0.02, 'land': 0.03},
    effects: Effects(army: 2, stability: 1),
    mood: 3,
    upkeepLine: 'civil',
    upkeep: 0.010,
    perk: 'logistics',
  ),
  ProjectDef(
    key: 'irrigation',
    name: 'ري وسدود',
    about: 'قنوات وسدود تزيد الغلة وتحمي المحصول من الجفاف.',
    fromYear: 1800,
    cost: 0.45,
    minHalves: 6,
    maxHalves: 14,
    lines: {'land': 0.05},
    mood: 2,
    upkeepLine: 'civil',
    upkeep: 0.008,
    perk: 'drought',
  ),
  ProjectDef(
    key: 'arsenal',
    name: 'ترسانة بحرية ومصنع بارود',
    about: 'تصنيع السفن والمدافع والبارود محليا بدل استيرادها.',
    fromYear: 1800,
    cost: 0.70,
    minHalves: 8,
    maxHalves: 16,
    effects: Effects(army: 4, foreign: 2),
    upkeepLine: 'army',
    upkeep: 0.012,
  ),
  ProjectDef(
    key: 'factories',
    name: 'مصانع نسيج وصناعات',
    about: 'مصانع حديثة تقلل الاستيراد وتخلق إيرادا وعمالة.',
    fromYear: 1800,
    cost: 0.60,
    minHalves: 8,
    maxHalves: 16,
    lines: {'other': 0.05, 'customs': 0.01},
    effects: Effects(foreign: 1, education: 1),
    upkeepLine: 'admin',
    upkeep: 0.008,
  ),
  ProjectDef(
    key: 'modern_army',
    name: 'الجيش النظامي الحديث',
    about: 'فرق مدربة على النظام الأوروبي بدل الجند التقليدي؛ يغضب الانكشارية.',
    fromYear: 1805,
    cost: 0.90,
    minHalves: 8,
    maxHalves: 16,
    effects: Effects(army: 8, foreign: 2, stability: -2),
    powers: {'janissaries': -10},
    upkeepLine: 'army',
    upkeep: 0.020,
    perk: 'tech',
  ),
  ProjectDef(
    key: 'military_academy',
    name: 'مدارس حربية حديثة',
    about: 'ضباط متعلمون بالهندسة والرياضيات والفرنسية.',
    fromYear: 1820,
    cost: 0.40,
    minHalves: 5,
    maxHalves: 10,
    effects: Effects(army: 6, education: 3),
    powers: {'ulema': -4},
    upkeepLine: 'army',
    upkeep: 0.008,
    perk: 'tech',
  ),
  ProjectDef(
    key: 'schools_modern',
    name: 'مدارس رشدية وإعدادية',
    about: 'تعليم حديث بعد الكتّاب يخرج موظفين وضباطا.',
    fromYear: 1830,
    cost: 0.45,
    minHalves: 6,
    maxHalves: 12,
    effects: Effects(education: 8),
    powers: {'ulema': -5},
    schools: 2500,
    literacy: 1.2,
    upkeepLine: 'civil',
    upkeep: 0.010,
  ),
  ProjectDef(
    key: 'quarantine',
    name: 'الحجر الصحي والمستشفيات',
    about: 'محاجر في الموانئ ومستشفيات تحد من أثر الطاعون والأوبئة.',
    fromYear: 1830,
    cost: 0.30,
    minHalves: 4,
    maxHalves: 10,
    effects: Effects(stability: 1),
    mood: 1,
    upkeepLine: 'civil',
    upkeep: 0.005,
    perk: 'plague',
  ),
  ProjectDef(
    key: 'ports',
    name: 'موانئ وأرصفة حديثة',
    about: 'أرصفة ومخازن ترفع حركة التجارة والجمارك.',
    fromYear: 1840,
    cost: 0.55,
    minHalves: 6,
    maxHalves: 12,
    lines: {'customs': 0.06},
    effects: Effects(foreign: 1),
    upkeepLine: 'admin',
    upkeep: 0.006,
    perk: 'trade',
  ),
  ProjectDef(
    key: 'land_registry',
    name: 'سجل الأراضي (الطابو)',
    about: 'مسح وتسجيل للأراضي يوسع الجباية ويقلل التهرب؛ يغضب الملتزمين.',
    fromYear: 1850,
    cost: 0.40,
    minHalves: 5,
    maxHalves: 10,
    lines: {'land': 0.06},
    corruption: -4,
    powers: {'tax_farmers': -8, 'governors': -3},
    upkeepLine: 'admin',
    upkeep: 0.005,
  ),
  ProjectDef(
    key: 'telegraph',
    name: 'شبكة تلغراف',
    about: 'أسلاك تربط العاصمة بالولايات: أوامر أسرع ورقابة أحكم.',
    fromYear: 1855,
    cost: 0.35,
    minHalves: 4,
    maxHalves: 8,
    effects: Effects(stability: 2, foreign: 2),
    corruption: -4,
    upkeepLine: 'admin',
    upkeep: 0.006,
    perk: 'logistics',
  ),
  ProjectDef(
    key: 'ottoman_bank',
    name: 'مصرف عثماني حديث',
    about: 'مصرف يصدر الأوراق ويقرض الدولة ويضبط النقد.',
    fromYear: 1855,
    cost: 0.30,
    minHalves: 4,
    maxHalves: 8,
    inflation: -1.5,
    powers: {'tax_farmers': -4, 'merchants': 5},
    upkeepLine: 'admin',
    upkeep: 0.004,
    perk: 'credit',
  ),
  ProjectDef(
    key: 'railway',
    name: 'سكك حديد رئيسية',
    about: 'خطوط تربط الموانئ بقلب الأناضول والروملي؛ أكبر مشروع في الكتالوج.',
    fromYear: 1856,
    cost: 1.20,
    minHalves: 12,
    maxHalves: 24,
    lines: {'customs': 0.05, 'land': 0.05, 'other': 0.02},
    effects: Effects(army: 4, stability: 2),
    mood: 4,
    upkeepLine: 'admin',
    upkeep: 0.015,
    perk: 'logistics',
  ),
  ProjectDef(
    key: 'mass_schools',
    name: 'التعليم الابتدائي الإلزامي',
    about: 'مدارس ابتدائية في كل ناحية ومعلمون مدربون.',
    fromYear: 1869,
    cost: 0.70,
    minHalves: 8,
    maxHalves: 16,
    effects: Effects(education: 8),
    powers: {'ulema': -4},
    schools: 8000,
    literacy: 3,
    upkeepLine: 'civil',
    upkeep: 0.015,
  ),
  ProjectDef(
    key: 'hijaz_railway',
    name: 'سكة حديد الحجاز',
    about: 'خط من دمشق إلى المدينة بتبرعات المسلمين: هيبة دينية وربط للحجاز.',
    fromYear: 1898,
    cost: 0.80,
    minHalves: 8,
    maxHalves: 14,
    effects: Effects(legitimacy: 5, foreign: 2, stability: 1),
    provinceMood: {'hijaz': 10, 'syria': 4},
    upkeepLine: 'admin',
    upkeep: 0.008,
    perk: 'logistics',
  ),
];

ProjectDef? projectDef(String key) {
  for (final d in projectCatalog) {
    if (d.key == key) return d;
  }
  return null;
}

bool isProjectKey(String key) => projectDef(key) != null;
