import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/settings.dart';

abstract class SettingsRepository {
  Future<Either<Failure, SettingsEntity>> getSettings();
  Future<Either<Failure, void>> saveSettings(SettingsEntity settings);
}
