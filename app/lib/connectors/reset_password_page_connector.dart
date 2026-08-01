import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/reset_password/actions/reset_password_action.dart';
import 'package:business/redux/reset_password/actions/set_confirm_password_action.dart';
import 'package:business/redux/reset_password/actions/set_password_action.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/reset_password_page.dart';

import '../common/validators.dart';
import '../navigation/go_action.dart';

@RoutePage()
class ResetPasswordPageConnector extends StatelessWidget {
  const ResetPasswordPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => ResetPasswordPage(
      password: vm.password,
      confirmPassword: vm.confirmPassword,
      onPressedResetPassword: vm.onPressedResetPassword,
      onPressedBackToLogin: vm.onPressedBackToLogin,
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ResetPasswordPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final password = resetPassword.password;

    return _Vm(
      password: FieldVm(
        value: password,
        validator: (v) => passwordValidator(v),
        onChanged: (v) => dispatchSync(SetPasswordAction(v)),
      ),
      confirmPassword: FieldVm(
        value: resetPassword.confirmPassword,
        validator: (v) =>
            passwordValidator(v) ?? passwordsMatchValidator(password, v),
        onChanged: (v) => dispatchSync(SetConfirmPasswordAction(v)),
      ),
      onPressedResetPassword: () => dispatch(ResetPasswordAction()),
      onPressedBackToLogin: () => dispatch(GoAction.pop()),
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.password,
    required this.confirmPassword,
    required this.onPressedResetPassword,
    required this.onPressedBackToLogin,
  }) : super(equals: [password, confirmPassword]);

  final FieldVm<String?> password;
  final FieldVm<String?> confirmPassword;
  final VoidCallback onPressedResetPassword;
  final VoidCallback onPressedBackToLogin;
}
