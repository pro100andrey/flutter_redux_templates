import 'package:flutter/material.dart';

class BaseCircleIndicator extends StatelessWidget {
  const BaseCircleIndicator({
    this.size = 30,
    this.color,
    this.strokeWidth,
    this.value,
    super.key,
  });

  final double size;
  final Color? color;
  final double? strokeWidth;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final width = size;
    final height = size;

    return Center(
      child: SizedBox(
        width: width,
        height: height,
        child: CircularProgressIndicator(
          value: value,
          color: color,
          strokeWidth: strokeWidth ?? 3,
        ),
      ),
    );
  }
}
