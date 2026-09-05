import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Hosted backend configuration (v0.2).
///
/// The app runs fully on-device when no backend is configured. Pass the
/// Supabase project at build time to switch on auth, the shared social graph,
/// comments, notifications and the hosted coach:
///
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///               --dart-define=SUPABASE_KEY=sb_publishable_...
class BackendConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const key = String.fromEnvironment('SUPABASE_KEY');

  /// Deep link the OAuth flow returns to on iOS and Android. Registered in
  /// AndroidManifest.xml and Info.plist; must also be an allowed redirect URL
  /// in the Supabase dashboard.
  static const mobileRedirect = 'io.ritmo://login-callback';

  static bool get enabled => url.isNotEmpty && key.isNotEmpty;

  static String get coachEndpoint => '$url/functions/v1/coach';
  static String get videoEndpoint => '$url/functions/v1/video';
}

/// Call once from main() before runApp. Safe no-op without configuration.
Future<void> initBackend() async {
  if (!BackendConfig.enabled) return;
  await sb.Supabase.initialize(
    url: BackendConfig.url,
    publishableKey: BackendConfig.key,
    authOptions: const sb.FlutterAuthClientOptions(authFlowType: sb.AuthFlowType.pkce),
  );
}

sb.SupabaseClient get supabase => sb.Supabase.instance.client;

/// The signed-in user, as much as the app needs to know.
class AuthUser {
  const AuthUser({required this.id, this.email});
  final String id;
  final String? email;
}

AuthUser? currentAuthUser() {
  if (!BackendConfig.enabled) return null;
  final u = supabase.auth.currentUser;
  return u == null ? null : AuthUser(id: u.id, email: u.email);
}

String? currentAccessToken() => BackendConfig.enabled ? supabase.auth.currentSession?.accessToken : null;

Stream<AuthUser?> authChanges() {
  if (!BackendConfig.enabled) return const Stream.empty();
  return supabase.auth.onAuthStateChange.map((s) {
    final u = s.session?.user;
    return u == null ? null : AuthUser(id: u.id, email: u.email);
  });
}

enum SignInProvider { apple, google }

/// Starts the OAuth dance. On web this redirects the page; on mobile it opens
/// the system browser and returns through [BackendConfig.mobileRedirect].
Future<void> signInWith(SignInProvider provider, {String? handle, String? name}) async {
  await supabase.auth.signInWithOAuth(
    provider == SignInProvider.apple ? sb.OAuthProvider.apple : sb.OAuthProvider.google,
    redirectTo: kIsWeb ? null : BackendConfig.mobileRedirect,
    authScreenLaunchMode: kIsWeb ? sb.LaunchMode.platformDefault : sb.LaunchMode.externalApplication,
  );
}

/// Email magic link. [handle]/[name] seed the profile row created by the
/// database trigger on first sign-up.
Future<void> signInWithEmail(String email, {String? handle, String? name, String? emoji}) async {
  await supabase.auth.signInWithOtp(
    email: email.trim(),
    emailRedirectTo: kIsWeb ? null : BackendConfig.mobileRedirect,
    data: {
      'handle': ?handle,
      'name': ?name,
      'emoji': ?emoji,
    },
  );
}

Future<void> signOut() async {
  if (!BackendConfig.enabled) return;
  await supabase.auth.signOut();
}
