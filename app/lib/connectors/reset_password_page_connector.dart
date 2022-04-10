import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/pages/reset_password_page.dart';

class ResetPasswordPageConnector extends StatelessWidget {
  const ResetPasswordPageConnector({
    Key? key,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) =>
      StoreConnector<AppState, _ResetPasswordPageVm>(
        debug: this,
        vm: () => _Factory(this),
        builder: (context, vm) => ResetPasswordPage(
          vm: ResetPasswordPageVm(
            isWaiting: vm.isWaiting,
          ),
        ),
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ResetPasswordPageConnector> {
  _Factory(ResetPasswordPageConnector widget) : super(widget);
  @override
  _ResetPasswordPageVm fromStore() => _ResetPasswordPageVm(
        isWaiting: false,
      );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _ResetPasswordPageVm extends Vm with EquatableMixin {
  _ResetPasswordPageVm({
    required this.isWaiting,
  });

  final bool isWaiting;

  @override
  List<Object?> get props => [isWaiting];
}
