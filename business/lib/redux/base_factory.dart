import 'package:async_redux/async_redux.dart';
import 'package:flutter/widgets.dart';

import 'app_state.dart';

abstract class BaseFactory<T extends Widget?, Model extends Vm>
    extends VmFactory<AppState, T, Model> {
  BaseFactory([super.connector]);
}
