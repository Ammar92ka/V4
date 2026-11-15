import 'package:flutter/material.dart';

import '../engine/game_engine.dart';
import '../models/game_state.dart';
import '../models/systems.dart';
import '../ui/theme.dart';
import '../widgets/line_chart.dart';

/// الرسوم البيانية: مسار الدولة عبر السنين (لقطة كل نصف سنة).
class ChartsScreen extends StatelessWidget {
  const ChartsScreen({super.key, required this.state});

  final GameState state;

  /// لقطات الحملة مع نقطة الحالة الحالية إن لم تكن مسجلة.
  List<StatPoint> _points() {
    final pts = List<StatPoint>.from(state.series);
    if (pts.isEmpty || pts.last.round != state.round) {
      pts.add(
        StatPoint(
          round: state.round,
          treasury: state.treasury,
          debt: state.debt,
          revenue: state.budget.totalRevenue,
          legitimacy: state.legitimacy,
          stability: state.stability,
          army: state.army,
          foreign: state.foreign,
          education: state.education,
          population: state.demog.population,
          literacy: state.demog.literacy,
          inflation: state.econ.inflation,
        ),
      );
    }
    return pts;
  }

  Widget _card(String title, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pts = _points();
    final first = GameEngine.yearOf(pts.first.round);
    final last = GameEngine.yearOf(pts.last.round);
    String millions(double v) => '${(v / 1e6).toStringAsFixed(1)} م';
    List<double> pick(num Function(StatPoint) f) => [for (final p in pts) f(p).toDouble()];

    const red = Color(0xFFE57373);
    const green = Color(0xFF81C784);
    const blue = Color(0xFF64B5F6);
    const purple = Color(0xFFBA68C8);
    const orange = Color(0xFFFFB74D);

    return Scaffold(
      appBar: AppBar(title: const Text('رسوم بيانية')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              'الخزينة والدين',
              LineChart(
                series: [
                  ChartSeries('الخزينة', green, pick((p) => p.treasury)),
                  ChartSeries('الدين', red, pick((p) => p.debt)),
                ],
                firstYear: first,
                lastYear: last,
                format: millions,
              ),
            ),
            _card(
              'الإيراد السنوي',
              LineChart(
                series: [ChartSeries('الإيراد', blue, pick((p) => p.revenue))],
                firstYear: first,
                lastYear: last,
                format: millions,
              ),
            ),
            _card(
              'الشرعية والاستقرار',
              LineChart(
                series: [
                  ChartSeries('الشرعية', AppColors.gold, pick((p) => p.legitimacy)),
                  ChartSeries('الاستقرار', green, pick((p) => p.stability)),
                ],
                firstYear: first,
                lastYear: last,
              ),
            ),
            _card(
              'الجيش والمكانة والتعليم',
              LineChart(
                series: [
                  ChartSeries('الجيش', red, pick((p) => p.army)),
                  ChartSeries('المكانة الدولية', blue, pick((p) => p.foreign)),
                  ChartSeries('التعليم', purple, pick((p) => p.education)),
                ],
                firstYear: first,
                lastYear: last,
              ),
            ),
            _card(
              'السكان (بالملايين)',
              LineChart(
                series: [ChartSeries('السكان', orange, pick((p) => p.population))],
                firstYear: first,
                lastYear: last,
                format: (v) => v.toStringAsFixed(1),
              ),
            ),
            _card(
              'القراءة والكتابة والتضخم',
              LineChart(
                series: [
                  ChartSeries('القراءة والكتابة %', purple, pick((p) => p.literacy)),
                  ChartSeries('التضخم %', red, pick((p) => p.inflation)),
                ],
                firstYear: first,
                lastYear: last,
                format: (v) => v.toStringAsFixed(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
