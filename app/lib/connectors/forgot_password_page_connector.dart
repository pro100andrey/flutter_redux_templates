import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/pages/forgot_password_page.dart';

class ForgotPasswordPageConnector extends StatelessWidget {
  const ForgotPasswordPageConnector({
    Key? key,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) =>
      StoreConnector<AppState, _ForgotPasswordPageVm>(
        debug: this,
        vm: () => _Factory(this),
        builder: (context, vm) => ForgotPasswordPage(
          vm: ForgotPasswordPageVm(
            isWaiting: vm.isWaiting,
          ),
        ),
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ForgotPasswordPageConnector> {
  _Factory(ForgotPasswordPageConnector widget) : super(widget);
  @override
  _ForgotPasswordPageVm fromStore() => _ForgotPasswordPageVm(
        isWaiting: false,
      );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _ForgotPasswordPageVm extends Vm with EquatableMixin {
  _ForgotPasswordPageVm({
    required this.isWaiting,
  });

  final bool isWaiting;

  @override
  List<Object?> get props => [isWaiting];
}
