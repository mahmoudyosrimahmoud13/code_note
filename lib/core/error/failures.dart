import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  @override
  List<Object> get props => [];
}

// General failures
class ServerFailure extends Failure {
  final String? message;
  ServerFailure([this.message]);

  @override
  List<Object> get props => [message ?? ''];
}

class CacheFailure extends Failure {
  final String? message;
  CacheFailure([this.message]);

  @override
  List<Object> get props => [message ?? ''];
}

class AuthFailure extends Failure {
  final String message;
  AuthFailure(this.message);

  @override
  List<Object> get props => [message];
}
