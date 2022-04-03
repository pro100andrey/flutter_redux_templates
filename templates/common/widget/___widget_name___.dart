import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

@immutable
class ___WidgetName___Vm extends Equatable {
  const ___WidgetName___Vm({
    this.onPressed,
  });

  final VoidCallback? onPressed;

  @override
  List<Object?> get props => [];
}

class ___WidgetName___ extends StatelessWidget {
  const ___WidgetName___({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final ___WidgetName___Vm vm;

  @override
  Widget build(BuildContext context) => Row(
        children: const [
          Text('___WidgetName___'),
        ],
      );
}