import 'package:equatable/equatable.dart';

class RoutersFlow extends Equatable {
  @override
  List<Object?> get props => [];
}

enum AuthFlowRedirection {
  login,
  resetPassword,
  createPassword;
}

class AuthFlow extends RoutersFlow {
  AuthFlow({
    required this.redirection,
  });

  final AuthFlowRedirection redirection;

  @override
  List<Object?> get props => [redirection];
}

class SplashFlow extends RoutersFlow {}

class HomeFlow extends RoutersFlow {}
