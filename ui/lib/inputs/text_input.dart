import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/value_changed.dart';

class BaseTextInput extends StatefulWidget {
  const BaseTextInput({
    required this.vm,
    this.obscureText = false,
    this.minLines,
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
    this.focusNode,
    this.changeWhenFocusEnd,
    this.inputFormatters,
    this.showCounterText = true,
    super.key,
  });

  final bool obscureText;
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
  final TextInputType? keyboardType;
  final List<String>? autofillHints;
  final bool? changeWhenFocusEnd;
  final bool showCounterText;
  final FocusNode? focusNode;
  final ValueChangedWithErrorVm<String> vm;

  final List<TextInputFormatter>? inputFormatters;

  @override
  _BaseTextInputState createState() => _BaseTextInputState();
}

class _BaseTextInputState extends State<BaseTextInput> {
  bool _isVisible = true;

  FocusNode? _focusNode;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        focusNode: _focusNode,
        autofillHints: widget.autofillHints,
        keyboardType: widget.keyboardType,
        minLines: widget.minLines,
        maxLength: widget.maxLength,
        maxLines: widget.maxLines,
        obscureText: _isVisible && widget.obscureText,
        inputFormatters: widget.inputFormatters,
        decoration: InputDecoration(
          counterText: widget.showCounterText ? null : '',
          enabled: widget.vm.enabled,
          labelText: widget.labelText,
          hintText: widget.hintText,
          helperText: widget.helperText,
          prefixText: widget.prefixText,
          prefixIcon: widget.prefixIcon,
          suffix: widget.suffix,
          suffixIcon: _prefixIcon(),
          filled: widget.filled,
          errorText: widget.vm.error,
        ),
      );

  Widget? _prefixIcon() => widget.obscureText
      ? IconButton(
          onPressed: _invertVisible,
          icon: Icon(
            _isVisible ? Icons.visibility_off : Icons.visibility,
          ),
        )
      : widget.vm.error != null
          ? Icon(
              Icons.error,
              color: Theme.of(context).errorColor,
            )
          : null;

  void _invertVisible() {
    setState(() {
      _isVisible = !_isVisible;
    });
  }

  final controller = TextEditingController();

  // ignore: prefer_function_declarations_over_variables
  late final _changeWhenFocusEndListener = () {
    final focusNode = _focusNode!;
    if (focusNode.hasFocus) {
      return;
    }

    widget.vm.onChanged(controller.text);
  };

  @override
  void initState() {
    super.initState();

    final changeWhenFocusEnd = widget.changeWhenFocusEnd ?? false;
    _focusNode = widget.focusNode ?? (changeWhenFocusEnd ? FocusNode() : null);

    if (changeWhenFocusEnd && _focusNode != null) {
      _focusNode?.addListener(_changeWhenFocusEndListener);
    } else {
      controller.addListener(() {
        final text = controller.text;
        final skip = widget.vm.value == null && text.isEmpty;
        if (widget.vm.value != text && !skip) {
          widget.vm.onChanged.call(text);
        }
      });
    }

    if (widget.vm.value != null) {
      controller.text = widget.vm.value!;
    }
  }

  @override
  void didUpdateWidget(BaseTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = widget.vm.value ?? '';
    if (controller.text != widget.vm.value) {
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

    _focusNode?.removeListener(_changeWhenFocusEndListener);

    super.dispose();
  }
}
