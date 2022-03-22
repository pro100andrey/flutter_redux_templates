import 'package:flutter/material.dart';

mixin BaseInput<T extends StatefulWidget> on State<T> {
  String? get value;
  ValueChanged<String>? get onUpdate;

  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();

    if (onUpdate != null) {
      controller.addListener(() {
        final text = controller.text;
        final skip = value == null && text.isEmpty;
        if (value != text && !skip) {
          onUpdate!(text);
        }
      });
    }

    if (value != null) {
      controller.text = value!;
    }
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = value ?? '';
    if (controller.text != value) {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.fromPosition(
          TextPosition(offset: text.length),
        ),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
