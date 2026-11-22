/// Build settings for CodeNote Online, set with --dart-define at build time
/// (see .github/workflows/build.yml and docs/online/BUILD.md).
class OnlineConfig {
  OnlineConfig._();

  /// `supabase` or `fastapi`.
  static const backend = String.fromEnvironment('BACKEND', defaultValue: 'fastapi');
  static bool get isSupabase => backend == 'supabase';
  static bool get isFastApi => !isSupabase;

  /// Supabase project (Settings > API in the Supabase dashboard).
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// FastAPI build: a server address to suggest on the first screen
  /// (people can still type their own).
  static const suggestedServer = String.fromEnvironment('SERVER_URL');

  /// Google sign-in. The Web client id is used as the "server client id"
  /// on Android so the backend can check the sign-in.
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Firebase, only for push. Without these, push is simply off.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseIosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');

  static bool get pushConfigured =>
      firebaseApiKey.isNotEmpty && firebaseAppId.isNotEmpty && firebaseSenderId.isNotEmpty && firebaseProjectId.isNotEmpty;

  static bool get googleConfigured => googleWebClientId.isNotEmpty;

  /// What the app calls its backend in settings.
  static String get backendLabel => isSupabase ? 'Supabase' : 'CodeNote server';
}
