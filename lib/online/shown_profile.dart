import '../features/settings/domain/entities/settings.dart';
import 'online_service.dart';

/// Who to show as "you" in the app: the signed-in CodeNote Online account,
/// or the local profile from Settings when nobody is signed in.
class ShownProfile {
  const ShownProfile({required this.name, required this.handle, required this.imageUrl, required this.seed, required this.online});

  final String name;
  final String handle; // without the @
  final String? imageUrl;
  final String seed;
  final bool online;

  factory ShownProfile.of(SettingsEntity? settings) {
    final me = OnlineService.instance.me;
    if (me != null) {
      return ShownProfile(
        name: me.name,
        handle: me.username ?? '',
        imageUrl: me.avatarUrl,
        seed: me.username ?? me.id,
        online: true,
      );
    }
    return ShownProfile(
      name: settings?.userName ?? 'You',
      handle: settings?.userHandle ?? '',
      imageUrl: settings?.profileImagePath,
      seed: settings?.userHandle ?? 'codenote',
      online: false,
    );
  }
}
