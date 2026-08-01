import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/registration/actions/registration_action.dart';
import 'package:business/redux/registration/actions/set_confirm_password_action.dart';
import 'package:business/redux/registration/actions/set_email_action.dart';
import 'package:business/redux/registration/actions/set_password_action.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/registration_page.dart';

import '../common/validators.dart';
import '../navigation/go_action.dart';

@RoutePage()
class RegistrationPageConnector extends StatelessWidget {
  const RegistrationPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => RegistrationPage(
      email: vm.email,
      password: vm.password,
      confirmPassword: vm.confirmPassword,
      onPressedRegister: vm.onPressedRegister,
      onPressedBackToLogin: vm.onPressedBackToLogin,
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, RegistrationPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final password = registration.password;

    return _Vm(
      email: FieldVm(
        value: registration.email,
        validator: (v) => emailValidator(v),
        onChanged: (v) => dispatchSync(SetEmailAction(v)),
      ),
      password: FieldVm(
        value: password,
        validator: (v) => passwordValidator(v),
        onChanged: (v) => dispatchSync(SetPasswordAction(v)),
      ),
      confirmPassword: FieldVm(
        value: registration.confirmPassword,
        validator: (v) =>
            passwordValidator(v) ?? passwordsMatchValidator(password, v),
        onChanged: (v) => dispatchSync(SetConfirmPasswordAction(v)),
      ),
      onPressedRegister: () async {
        final status = await dispatchAndWait(RegistrationAction());
        if (status.isCompletedOk) {
          dispatch(GoAction.pop());
        }
      },
      onPressedBackToLogin: () => dispatch(GoAction.pop()),
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.onPressedRegister,
    required this.onPressedBackToLogin,
  }) : super(equals: [email, password, confirmPassword]);

  final FieldVm<String?> email;
  final FieldVm<String?> password;
  final FieldVm<String?> confirmPassword;
  final VoidCallback onPressedRegister;
  final VoidCallback onPressedBackToLogin;
}
