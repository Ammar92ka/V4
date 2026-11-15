import '../models/game_state.dart';
import '../models/systems.dart';
import 'debt.dart';
import 'foreign.dart';
import 'projects.dart';
import 'provinces.dart';
import 'sim_common.dart';

/// نظام الحروب: تحسبه اللعبة بالأرقام (قوة جيشنا وقوة العدو ونقاط الحرب)،
/// ويكتب الذكاء الاصطناعي سرده فقط. للحرب كلفة وخسائر ونتائج: تعويض وتنازل عن ولايات.
class WarRules {
  WarRules._();

  static const int maxWars = 2;

  /// الإنهاك: بعد هذا العدد من أنصاف السنة يتوقف القتال بسلام متكافئ.
  static const int exhaustionHalves = 14;
  static const double peaceShare = 0.005;

  /// الولاية التي تقع على جبهة كل دولة (للتنازل والحكم الذاتي بعد الهزيمة).
  static const Map<String, String> frontProvince = {
    'russia': 'rumelia',
    'austria': 'rumelia',
    'germany': 'rumelia',
    'britain': 'egypt',
    'france': 'egypt',
    'persia': 'iraq',
  };

  static War? warWith(GameState s, String enemy) {
    for (final w in s.wars) {
      if (w.enemy == enemy) return w;
    }
    return null;
  }

  /// قوتنا الفعلية في القتال: الجيش × التحديث × الخدمات اللوجستية × المعنويات × الإمداد.
  static double ourPower(GameState s) {
    var tech = 1 + 0.004 * (s.education - 15);
    tech += (ProjectRules.perkCount(s, 'tech') * 0.08).clamp(0.0, 0.2).toDouble();
    final logistics = 1 + (ProjectRules.perkCount(s, 'logistics') * 0.05).clamp(0.0, 0.2).toDouble();
    final morale = 0.8 + 0.4 * s.stability / 100;
    final supply = s.treasury > 0 ? 1.0 : 0.85;
    final p = s.army * tech * logistics * morale * supply;
    return p < 1 ? 1 : p;
  }

  /// قوة العدو: جيشه مضروبا في عامل اقتصادي (اقتصاد أكبر = إمداد أفضل).
  static double enemyPower(CountryState c) =>
      c.military * (0.8 + 0.2 * (c.economy / 100).clamp(0.3, 3.0).toDouble());

  /// نسبة تفوقنا في الحرب من 0 إلى 1 (0.5 تكافؤ).
  static double ratio(GameState s, CountryState c) {
    final our = ourPower(s);
    return our / (our + enemyPower(c));
  }

  /// كلفة الحروب الجارية في نصف السنة، فوق ميزانية الجيش.
  static double costs(GameState s) {
    var total = 0.0;
    for (final w in s.wars) {
      final c = s.countries[w.enemy];
      if (c == null) continue;
      final r = enemyPower(c) / ourPower(s);
      total += s.budget.totalRevenue * 0.04 * r.clamp(0.5, 2.0).toDouble();
    }
    return total;
  }

  /// يعلن حربا. يعيد جملة للتقرير أو نصا فارغا إن لم يمكن.
  static String declare(GameState s, String enemy, {required bool byUs}) {
    final c = s.countries[enemy];
    if (c == null || warWith(s, enemy) != null || s.wars.length >= maxWars) return '';
    s.wars.add(War(enemy, s.round, byUs: byUs));
    c.relation = clampD(c.relation - 10, 0, 100);
    return byUs ? 'أعلنت الدولة الحرب على ${c.name}' : 'أعلنت ${c.name} الحرب علينا';
  }

  static String describe(War w) {
    if (w.score >= 30) return 'تميل لصالحنا';
    if (w.score <= -30) return 'تميل ضدنا';
    return 'متكافئة';
  }

  /// معارك نصف السنة، والسلام التلقائي، وحروب جديدة قد تفتحها الدول المعادية.
  static List<String> step(GameState s) {
    final notes = <String>[];
    final rng = rngFor(s, 31);

    for (final w in List<War>.from(s.wars)) {
      final c = s.countries[w.enemy];
      if (c == null) {
        s.wars.remove(w);
        continue;
      }
      w.halves += 1;
      final r = ratio(s, c);
      var allies = 0;
      for (final o in s.countries.values) {
        if (o.key != w.enemy && o.relation >= 75 && warWith(s, o.key) == null) allies++;
      }
      final delta = (r - 0.5) * 30 +
          (w.byUs ? 0 : 3) -
          w.halves * 0.3 +
          allies * 2 +
          (rng.nextDouble() * 12 - 6);
      w.score = clampD(w.score + delta, -100, 100);

      // الخسائر: أشد عند ضعفنا
      final loss = 0.5 + 1.5 * (1 - r);
      final whole = loss.floor();
      s.army = (s.army - whole - (rng.nextDouble() < loss - whole ? 1 : 0)).clamp(0, 100).toInt();
      s.demog.population = clampD(s.demog.population * (1 - 0.0015 * (1 - r)), 1, 500);
      s.stab.shift('social', -0.5);
      c.relation = clampD(c.relation - 1, 0, 100);
      if (w.halves % 4 == 0) {
        if (w.score >= 40) s.legitimacy = (s.legitimacy + 1).clamp(0, 100).toInt();
        if (w.score <= -30) s.legitimacy = (s.legitimacy - 1).clamp(0, 100).toInt();
      }
      if (w.halves % 2 == 0) {
        if (w.score >= 30) s.foreign = (s.foreign + 1).clamp(0, 100).toInt();
        if (w.score <= -30) s.foreign = (s.foreign - 1).clamp(0, 100).toInt();
      }
      notes.add('الحرب مع ${c.name}: ${describe(w)} (نقاط ${w.score.round()})');

      if (w.score >= 60) {
        notes.add(_conclude(s, w, w.score));
      } else if (w.score <= -60) {
        notes.add(_conclude(s, w, w.score));
      } else if (w.halves >= exhaustionHalves) {
        notes.add(_conclude(s, w, 0));
      }
    }

    // حروب جديدة: الدول المعادية الأقوى تهاجم الأضعف
    if (!inGrace(s)) {
      var i = 0;
      for (final c in s.countries.values) {
        i++;
        if (s.wars.length >= maxWars || warWith(s, c.key) != null || c.relation >= 22) continue;
        final strength = (enemyPower(c) / ourPower(s)).clamp(0.6, 2.0).toDouble();
        final p = (0.015 + (22 - c.relation) * 0.004) * strength * s.diff.events;
        if (rngFor(s, 800 + i).nextDouble() < p) {
          final msg = declare(s, c.key, byUs: false);
          if (msg.isNotEmpty) notes.add(msg);
        }
      }
    }
    return notes;
  }

  /// يطلب الصلح من الديوان: يكلف إجراء، وشروطه تتبع موقفنا في الحرب (مع مجاملة 15 نقطة).
  static CourtResult seekPeace(GameState s, String enemy) {
    final w = warWith(s, enemy);
    if (w == null) return const CourtResult(false, 'لا حرب مع هذه الدولة');
    if (w.halves < 2) return const CourtResult(false, 'لا يقبل العدو التفاوض في الشهور الأولى');
    final cost = costShare(s, peaceShare);
    if (s.courtActions <= 0) return const CourtResult(false, 'استنفدت إجراءات الديوان لنصف السنة هذا');
    if (s.treasury < cost) return const CourtResult(false, 'الخزينة لا تكفي');
    s.treasury -= cost;
    s.courtActions -= 1;
    s.courtLog.add('طلب الصلح من ${w.enemyName}');
    final text = _conclude(s, w, w.score + 15);
    return CourtResult(true, text);
  }

  /// صلح بقرار من خيار ذكاء اصطناعي (بلا كلفة إجراء).
  static String peaceFromDecision(GameState s, String enemy) {
    final w = warWith(s, enemy);
    if (w == null) return '';
    return _conclude(s, w, w.score + 15);
  }

  static ProvinceState? _target(GameState s, String enemy) {
    final key = frontProvince[enemy];
    final p = key == null ? null : s.econ.provinces[key];
    if (p != null && !p.isLost) return p;
    ProvinceState? best;
    for (final q in s.econ.provinces.values) {
      if (q.isLost || q.key == 'anatolia') continue;
      if (best == null || q.def.sep > best.def.sep) best = q;
    }
    return best;
  }

  /// ينهي الحرب بشروط تتبع [x] (نقاط الحرب المعدلة). يعيد وصف النتيجة.
  static String _conclude(GameState s, War w, double x) {
    final c = s.countries[w.enemy]!;
    final rev = s.budget.totalRevenue;
    final name = c.name;
    String text;
    if (x >= 60) {
      s.treasury += rev * 0.15;
      s.foreign = (s.foreign + 4).clamp(0, 100).toInt();
      s.legitimacy = (s.legitimacy + 4).clamp(0, 100).toInt();
      c.relation = 25;
      c.military = clampD(c.military * 0.9, 8, 300);
      text = 'انتصرنا على $name وفرضنا عليها تعويضا وصلحا مشرفا';
    } else if (x >= 20) {
      s.treasury += rev * 0.05;
      s.foreign = (s.foreign + 2).clamp(0, 100).toInt();
      c.relation = 30;
      text = 'صلح مع $name بشروط لصالحنا';
    } else if (x > -20) {
      c.relation = 30;
      text = 'صلح مع $name بلا غالب ولا مغلوب';
    } else if (x > -60) {
      DebtRules.addForeign(s, rev * 0.12);
      s.foreign = (s.foreign - 3).clamp(0, 100).toInt();
      s.legitimacy = (s.legitimacy - 3).clamp(0, 100).toInt();
      final p = _target(s, w.enemy);
      if (p != null) p.autonomy = clampD(p.autonomy + 25, 0, 100);
      c.relation = 30;
      text = 'صلح مع $name بشروط قاسية: تعويض حرب وامتيازات في الحدود';
    } else {
      DebtRules.addForeign(s, rev * 0.25);
      s.foreign = (s.foreign - 6).clamp(0, 100).toInt();
      s.legitimacy = (s.legitimacy - 6).clamp(0, 100).toInt();
      s.stab.shift('political', -4);
      s.army = (s.army - 6).clamp(0, 100).toInt();
      final p = _target(s, w.enemy);
      final lost = p == null ? '' : '؛ ${ProvinceRules.lose(s, p, how: 'cession')}';
      c.relation = 30;
      text = 'هزيمة أمام $name وصلح مذل: تعويض ثقيل$lost';
    }
    s.wars.remove(w);
    s.countries[w.enemy]?.military = clampD(s.countries[w.enemy]!.military, 8, 300);
    return text;
  }

  /// نسبة الضعف في الجيش مقابل أقوى عدو (للتحذيرات).
  static double worstRatio(GameState s) {
    var worst = 1.0;
    for (final c in s.countries.values) {
      final r = ForeignRules.milRatio(s, c);
      if (r > worst) worst = r;
    }
    return worst;
  }
}
