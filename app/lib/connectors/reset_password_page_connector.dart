import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/reset_password/actions/reset_password_action.dart';
import 'package:business/redux/reset_password/actions/set_confirm_password_action.dart';
import 'package:business/redux/reset_password/actions/set_password_action.dart';
import 'package:business/redux/reset_password/reset_password_selectors.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/reset_password_page.dart';

import '../common/validators.dart';
import '../routes.dart';

class ResetPasswordPageConnector extends StatelessWidget {
  const ResetPasswordPageConnector({
    super.key,
  });

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
class _Factory extends VmFactory<AppState, ResetPasswordPageConnector> {
  _Factory(ResetPasswordPageConnector super.widget);

  @override
  _Vm fromStore() {
    final password = selectResetPasswordPassword(state);
    final passwordError = passwordValidator(password);
    final confirmPassword = selectResetPasswordConfirmPassword(state);
    final confirmPasswordError = passwordValidator(confirmPassword);
    final passwordsMatchError =
        passwordsMatchValidator(password, confirmPassword);
    final formIsValid = selectResetPasswordDataIsSet(state) &&
        passwordError == null &&
        confirmPasswordError == null &&
        passwordsMatchError == null;

    return _Vm(
      password: ValueChangedWithErrorVm(
        value: password,
        error: passwordError,
        onChanged: (password) => dispatch(
          SetPasswordAction(password),
        ),
      ),
      confirmPassword: ValueChangedWithErrorVm(
        value: confirmPassword,
        error: confirmPasswordError ?? passwordsMatchError,
        onChanged: (confirmPassword) => dispatch(
          SetConfirmPasswordAction(confirmPassword),
        ),
      ),
      onPressedResetPassword: formIsValid
          ? () => dispatch(
                ResetPasswordAction(),
              )
          : null,
      onPressedBackToLogin: routemaster.pop,
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm with EquatableMixin {
  _Vm({
    required this.password,
    required this.confirmPassword,
    required this.onPressedResetPassword,
    required this.onPressedBackToLogin,
  });

  final ValueChangedWithErrorVm<String> password;
  final ValueChangedWithErrorVm<String> confirmPassword;
  final VoidCallback? onPressedResetPassword;
  final VoidCallback? onPressedBackToLogin;

  @override
  List<Object?> get props => [password, confirmPassword];
}
