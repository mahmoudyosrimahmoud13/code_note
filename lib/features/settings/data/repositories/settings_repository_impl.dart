import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_local_data_source.dart';
import '../models/settings_model.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsLocalDataSource localDataSource;

  SettingsRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, SettingsEntity>> getSettings() async {
    try {
      final settings = await localDataSource.getSettings();
      return Right(settings);
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> saveSettings(SettingsEntity settings) async {
    try {
      await localDataSource.cacheSettings(SettingsModel.fromEntity(settings));
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure());
    }
  }
}
