import 'package:flutter/material.dart';

class RoundedButton extends StatelessWidget {
  const RoundedButton({
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
    final minWidth = width;
    final maxWidth = width;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minWidth,
        maxWidth: maxWidth,
        minHeight: height,
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          onPrimary: foregroundColor,
          primary: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: borderColor != null
                ? BorderSide(color: borderColor!)
                : BorderSide.none,
          ),
        ),
        onPressed: onPressed,
        child: Text(title),
      ),
    );
  }
}
