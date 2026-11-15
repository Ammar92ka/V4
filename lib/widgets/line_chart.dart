import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// سلسلة بيانات واحدة في الرسم.
class ChartSeries {
  final String label;
  final Color color;
  final List<double> values;
  const ChartSeries(this.label, this.color, this.values);
}

/// رسم خطي بسيط بلا مكتبات: كل السلاسل على مقياس واحد من أصغر قيمة إلى أكبرها.
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.series,
    required this.firstYear,
    required this.lastYear,
    this.height = 190,
    this.format,
  });

  final List<ChartSeries> series;
  final int firstYear;
  final int lastYear;
  final double height;

  /// تنسيق قيمة المحور (مثلا للملايين).
  final String Function(double)? format;

  @override
  Widget build(BuildContext context) {
    final all = [for (final s in series) ...s.values];
    if (all.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(child: Text('لا بيانات بعد: العب جولة واحدة على الأقل.', style: TextStyle(color: AppColors.muted))),
      );
    }
    var lo = all.reduce((a, b) => a < b ? a : b);
    var hi = all.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-9) {
      hi = lo + 1;
    }
    String f(double v) => (format ?? (x) => x.round().toString())(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(s.label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          width: double.infinity,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: CustomPaint(painter: _ChartPainter(series, lo, hi)),
          ),
        ),
        const SizedBox(height: 4),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$firstYear', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              Text('أدنى ${f(lo)} • أعلى ${f(hi)}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              Text('$lastYear', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.series, this.lo, this.hi);

  final List<ChartSeries> series;
  final double lo;
  final double hi;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AppColors.cardBorder
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (final s in series) {
      if (s.values.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      final path = Path();
      final n = s.values.length;
      for (var i = 0; i < n; i++) {
        final x = n == 1 ? size.width / 2 : size.width * i / (n - 1);
        final y = size.height - (s.values[i] - lo) / (hi - lo) * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.series != series || old.lo != lo || old.hi != hi;
}
