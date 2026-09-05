import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/backend.dart';
import '../../core/providers.dart';

/// Sign in with Apple, Google or an email magic link (v0.2).
///
/// Signing in is optional: the app is fully usable on-device. An account
/// puts your posts, routines and follows on the shared graph and unlocks the
/// hosted coach with its free weekly quota.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _linkSent = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) toast(context, 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final auth = ref.watch(authProvider);
    final me = ref.watch(profileProvider);

    if (auth != null && !_busy) {
      // Signed in while this screen was open (OAuth returned): go home.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.canPop()) context.pop();
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (!BackendConfig.enabled) ...[
            const EmptyState(
              emoji: '🔌',
              title: 'Demo build',
              body: 'This build has no hosted backend. Run with --dart-define=SUPABASE_URL and SUPABASE_KEY to enable accounts, the shared feed and the cloud coach.',
            ),
          ] else if (auth != null) ...[
            Text('Signed in', style: t.headlineMedium),
            const SizedBox(height: 6),
            Text(auth.email ?? auth.id, style: t.bodyMedium),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(signOut),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ] else ...[
            Text('Train together, everywhere.', style: t.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'An account puts your routines, posts and follows on the shared Ritmo graph, syncs across devices, and turns on the cloud coach with 5 free messages a week.',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : () => _run(() => signInWith(SignInProvider.apple)),
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.apple),
              label: const Text('Continue with Apple'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : () => _run(() => signInWith(SignInProvider.google)),
              style: FilledButton.styleFrom(backgroundColor: SoColors.surface2, foregroundColor: SoColors.text, minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: const Text('Continue with Google'),
            ),
            const SizedBox(height: 24),
            Row(children: [
              const Expanded(child: Divider()),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('or email', style: t.bodySmall)),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 16),
            if (_linkSent)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: SoColors.mintSoft, borderRadius: BorderRadius.circular(12)),
                child: Text('Magic link sent to ${_email.text.trim()}. Open it on this device to finish signing in.', style: t.bodyMedium?.copyWith(color: SoColors.mint)),
              )
            else ...[
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(hintText: 'you@example.com', prefixIcon: Icon(Icons.mail_outline)),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _busy || !_email.text.contains('@')
                    ? null
                    : () => _run(() async {
                          await signInWithEmail(_email.text, handle: me?.handle, name: me?.name, emoji: me?.emoji);
                          setState(() => _linkSent = true);
                        }),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Email me a sign-in link'),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Your step counts stay on the device until you tap Share. Signing in is optional and you can delete the account any time from Settings.',
              style: t.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
