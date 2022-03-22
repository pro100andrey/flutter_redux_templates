import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

@immutable
class StyledButtonVm extends Equatable {
  const StyledButtonVm({
    required this.title,
    this.onPressed,
  });

  final String title;
  final VoidCallback? onPressed;

  @override
  List<Object?> get props => [title, onPressed == null];
}

class StyledButton extends StatelessWidget {
  const StyledButton({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final StyledButtonVm vm;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: vm.onPressed,
        child: Text(vm.title),
      );
}
