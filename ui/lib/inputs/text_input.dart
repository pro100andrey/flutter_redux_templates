import 'package:flutter/material.dart';
import '../models/value_changed.dart';

class TextInput extends StatefulWidget {
  const TextInput({
    required this.vm,
    this.obscureText = false,
    this.maxLines = 1,
    this.labelText,
    this.hintText,
    this.helperText,
    this.prefixText,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.autofillHints,
    this.filled,
    this.maxLength,
    Key? key,
  }) : super(key: key);

  final bool obscureText;
  final int maxLines;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? prefixText;
  final Widget? suffix;
  final Widget? prefixIcon;
  final int? maxLength;
  final bool? filled;
  final TextInputType? keyboardType;
  final List<String>? autofillHints;
  final ValueChangedWithErrorVm<String> vm;

  @override
  _TextInputState createState() => _TextInputState();
}

class _TextInputState extends State<TextInput> {
  bool _isVisible = true;

  @override
  Widget build(BuildContext context) => TextField(
        style: Theme.of(context).textTheme.bodyText1,
        controller: controller,
        autofillHints: widget.autofillHints,
        keyboardType: widget.keyboardType,
        maxLength: widget.maxLength,
        maxLines: widget.maxLines,
        obscureText: _isVisible && widget.obscureText,
        decoration: InputDecoration(
          enabled: widget.vm.onChanged != null,
          labelText: widget.labelText,
          hintText: widget.hintText,
          helperText: widget.helperText,
          prefixText: widget.prefixText,
          prefixIcon: widget.prefixIcon,
          suffix: widget.suffix,
          suffixIcon: widget.obscureText
              ? IconButton(
                  onPressed: () {
                    setState(() {
                      _isVisible = !_isVisible;
                    });
                  },
                  icon: Icon(
                    _isVisible
                        ? Icons.visibility_off
                        : Icons.visibility_outlined,
                  ),
                )
              : null,
          filled: widget.filled,
          errorText: widget.vm.error,
        ),
      );

  final controller = TextEditingController();

  ValueChanged<String>? get onChanged => widget.vm.onChanged;
  String? get value => widget.vm.value;

  @override
  void initState() {
    super.initState();

    if (onChanged != null) {
      controller.addListener(() {
        final text = controller.text;
        final skip = value == null && text.isEmpty;
        if (value != text && !skip) {
          onChanged!.call(text);
        }
      });
    }

    if (value != null) {
      controller.text = value!;
    }
  }

  @override
  void didUpdateWidget(TextInput oldWidget) {
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
