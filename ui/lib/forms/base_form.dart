import 'package:flutter/widgets.dart';

/// Thin wrapper over [Form]: owns the form key, exposes a validate + save API,
/// and — since validator messages are localized — re-runs validation when the
/// locale changes so already-shown errors re-translate.
///
/// The [builder] receives the [BaseFormState] so submit buttons can call
/// `form.validateAndSave()`.
class BaseForm extends StatefulWidget {
  const BaseForm({
    required this.builder,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
    super.key,
  });

  final Widget Function(BuildContext context, BaseFormState form) builder;
  final AutovalidateMode autovalidateMode;

  @override
  BaseFormState createState() => BaseFormState();
}

class BaseFormState extends State<BaseForm> {
  final _formKey = GlobalKey<FormState>();
  Locale? _locale;
  var _didValidate = false;

  @override
  void initState() {
    super.initState();
    _didValidate = widget.autovalidateMode == AutovalidateMode.always;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Locale is an inherited dependency, so this fires when it changes.
    final locale = Localizations.localeOf(context);
    if (_locale != null && _locale != locale && _didValidate) {
      // Re-validate after the subtree rebuilds under the new locale.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _formKey.currentState?.validate();
      });
    }
    _locale = locale;
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    autovalidateMode: widget.autovalidateMode,
    onChanged: () {
      if (!_didValidate &&
          widget.autovalidateMode != AutovalidateMode.disabled) {
        _didValidate = true;
      }
    },
    child: widget.builder(context, this),
  );

  /// Validates and saves the form. Returns true when valid.
  bool validateAndSave() {
    _didValidate = true;
    final state = _formKey.currentState;
    if (state != null && state.validate()) {
      state.save();
      return true;
    }
    return false;
  }
}
