import 'package:flutter/material.dart' hide BoxDecoration, BoxShadow;
import 'package:flutter/services.dart';

import '../models/value_changed.dart';

class BaseTextInput extends StatefulWidget {
  const BaseTextInput({
    required this.vm,
    this.obscureText = false,
    this.autofocus = false,
    this.showCounterText = true,
    this.expands = false,
    this.minLines,
    this.maxLines = 1,
    this.labelText,
    this.hintText,
    this.helperText,
    this.prefixText,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.textAlignVertical,
    this.filled,
    this.maxLength,
    this.focusNode,
    this.inputFormatters,
    this.autofillHints,
    this.floatingLabelBehavior,
    this.onSubmitted,
    super.key,
  });

  final ValueChangedWithErrorVm<String?> vm;
  final bool obscureText;
  final bool autofocus;
  final bool showCounterText;
  final bool expands;
  final int? minLines;
  final int? maxLines;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? prefixText;
  final Widget? suffix;
  final Widget? prefixIcon;
  final int? maxLength;
  final bool? filled;
  final TextAlignVertical? textAlignVertical;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final List<String>? autofillHints;
  final FloatingLabelBehavior? floatingLabelBehavior;
  final void Function(String value)? onSubmitted;

  @override
  BaseTextInputState createState() => BaseTextInputState();
}

class BaseTextInputState extends State<BaseTextInput> {
  bool _isVisible = true;

  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();

    _controller.addListener(_controllerChangeListener);

    if (widget.vm.value != null) {
      _controller.text = widget.vm.value!;
    }
  }

  void _controllerChangeListener() {
    final text = _controller.text;
    final skip = widget.vm.value == null && text.isEmpty;
    if (widget.vm.value != text && !skip) {
      widget.vm.onChangedSync(text);
    }
  }

  @override
  void didUpdateWidget(BaseTextInput oldWidget) {
    final text = widget.vm.value ?? '';
    if (_controller.text != text) {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.fromPosition(
          TextPosition(offset: text.length),
        ),
      );
    }

    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    focusNode: widget.focusNode,
    keyboardType: widget.keyboardType,
    expands: widget.expands,
    minLines: widget.minLines,
    maxLength: widget.maxLength,
    maxLines: widget.maxLines,
    obscureText: _isVisible && widget.obscureText,
    autofocus: widget.autofocus,
    inputFormatters: widget.inputFormatters,
    onSubmitted: widget.onSubmitted,
    autofillHints: widget.autofillHints,
    textAlignVertical: widget.textAlignVertical,
    decoration: InputDecoration(
      floatingLabelBehavior: widget.floatingLabelBehavior,
      fillColor: Colors.transparent,
      counterText: widget.showCounterText ? null : '',
      enabled: widget.vm.enabled,
      labelText: widget.labelText,
      hintText: widget.hintText,
      helperText: widget.helperText,
      prefixText: widget.prefixText,
      prefixIcon: widget.prefixIcon,
      suffix: widget.suffix,
      suffixIcon: widget.obscureText
          ? IconButton(
              onPressed: _invertVisible,
              icon: Icon(_isVisible ? Icons.visibility_off : Icons.visibility),
            )
          : null,
      filled: widget.filled,
      errorText: widget.vm.error,
    ),
  );

  void _invertVisible() {
    setState(() {
      _isVisible = !_isVisible;
    });
  }
}
