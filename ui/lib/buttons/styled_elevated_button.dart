import 'package:flutter/material.dart';

class StyledElevatedButton extends StatelessWidget {
  const StyledElevatedButton({
    required this.title,
    required this.onPressed,
    this.borderColor,
    this.backgroundColor,
    this.foregroundColor,
    this.width = 200,
    this.height = 48,
    this.borderRadius = const BorderRadius.all(Radius.circular(25)),
    super.key,
  });

  final Color? borderColor;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final double width;
  final double height;
  final BorderRadiusGeometry borderRadius;
  final String title;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).elevatedButtonTheme.style;

    final newStyle = ElevatedButton.styleFrom(
      minimumSize: Size(width, height),
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      shape: borderColor != null
          ? RoundedRectangleBorder(
              borderRadius: borderRadius,
              side: BorderSide(color: borderColor!),
            )
          : null,
    );

    return ElevatedButton(
      style: style?.merge(newStyle),
      onPressed: onPressed,
      child: Text(title),
    );
  }
}
