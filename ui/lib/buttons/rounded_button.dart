import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';


@immutable
class RoundedButtonVm extends Equatable {
  const RoundedButtonVm({
    required this.title,
    required this.onPressed,
  });

  final String title;
  final VoidCallback? onPressed;

  @override
  List<Object?> get props => [onPressed == null];
}

class RoundedButton extends StatelessWidget {
  const RoundedButton({
    required this.vm,
    this.borderColor,
    this.backgroundColor,
    this.foregroundColor,
    this.width = 150,
    this.height = 48,
    this.borderRadius = const BorderRadius.all(Radius.circular(25)),
    Key? key,
  }) : super(key: key);

  final Color? borderColor;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final double width;
  final double height;
  final BorderRadiusGeometry borderRadius;
  final RoundedButtonVm vm;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: width,
          maxWidth: width,
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
          onPressed: vm.onPressed,
          child: Text(vm.title),
        ),
      );
}
