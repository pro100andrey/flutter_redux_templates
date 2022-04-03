import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

@immutable
class BaseTextButtonVm extends Equatable {
  const BaseTextButtonVm({
    required this.title,
    this.onPressed,
  });

  final String title;
  final VoidCallback? onPressed;

  @override
  List<Object?> get props => [onPressed == null, title];
}

class BaseTextButton extends StatelessWidget {
  const BaseTextButton({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final BaseTextButtonVm vm;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: vm.onPressed,
        child: Text(vm.title),
      );
}
