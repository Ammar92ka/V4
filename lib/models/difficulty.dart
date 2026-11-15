/// مستوى الصعوبة: يضبط وفرة الإيراد وتكرار الكوارث والمؤامرات والحروب وشدة القرارات الخاسرة.
class Difficulty {
  final int level;
  const Difficulty(this.level);

  static const List<String> names = ['سهل', 'عادي', 'صعب'];

  static const List<String> descriptions = [
    'إيراد أوفر بـ6%، وأحداث أقل، وخسائر القرارات أخف.',
    'التوازن الأساسي للعبة.',
    'إيراد أقل بـ6%، وأحداث أكثر، وخسائر القرارات أثقل.',
  ];

  int get safeLevel => level.clamp(0, 2).toInt();
  String get name => names[safeLevel];

  /// مضاعف الإيراد المحصل.
  double get revenue => const [1.06, 1.0, 0.94][safeLevel];

  /// مضاعف احتمال الكوارث والمؤامرات والحروب والانفصال.
  double get events => const [0.7, 1.0, 1.3][safeLevel];

  /// مضاعف الآثار السلبية للقرارات (أثر سالب × هذا).
  double get losses => const [0.8, 1.0, 1.25][safeLevel];
}
