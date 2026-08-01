import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/forgot_password/actions/forgot_password_action.dart';
import 'package:business/redux/forgot_password/actions/set_email_action.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/forgot_password_page.dart';

import '../common/validators.dart';
import '../navigation/go_action.dart';

@RoutePage()
class ForgotPasswordPageConnector extends StatelessWidget {
  const ForgotPasswordPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => ForgotPasswordPage(
      email: vm.email,
      onPressedResetPassword: vm.onPressedResetPassword,
      onPressedBackToLogin: vm.onPressedBackToLogin,
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ForgotPasswordPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(
    email: FieldVm(
      value: forgotPassword.email,
      validator: (v) => emailValidator(v),
      onChanged: (v) => dispatchSync(SetEmailAction(v)),
    ),
    onPressedResetPassword: () => dispatch(ForgotPasswordAction()),
    onPressedBackToLogin: () => dispatch(GoAction.pop()),
  );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.email,
    required this.onPressedResetPassword,
    required this.onPressedBackToLogin,
  }) : super(equals: [email]);

  final FieldVm<String?> email;
  final VoidCallback onPressedResetPassword;
  final VoidCallback onPressedBackToLogin;
}
