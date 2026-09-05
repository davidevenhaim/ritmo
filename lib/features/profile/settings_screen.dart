import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/backend.dart';
import '../../core/providers.dart';
import '../onboarding/onboarding_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final _key = TextEditingController(text: ref.read(settingsProvider).apiKey);
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SectionTitle('You'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline, color: SoColors.violet),
            title: const Text('Profile and goals'),
            subtitle: const Text('Name, body stats, goal, step target, diet, equipment'),
            trailing: const Icon(Icons.chevron_right, color: SoColors.muted),
            onTap: () {
              final me = ref.read(profileProvider);
              if (me != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnboardingScreen(initial: me)));
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined, color: SoColors.violet),
            title: const Text('My public profile'),
            subtitle: const Text('Posts, badges, followers, people you follow'),
            trailing: const Icon(Icons.chevron_right, color: SoColors.muted),
            onTap: () => context.push('/profile'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insights_outlined, color: SoColors.coral),
            title: const Text('Creator studio'),
            subtitle: const Text('For trainers, studios and clubs who publish'),
            trailing: const Icon(Icons.chevron_right, color: SoColors.muted),
            onTap: () => context.push('/studio'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.volunteer_activism_outlined, color: SoColors.mint),
            title: const Text('Free for everyone'),
            subtitle: const Text('No paywall, no limits for individuals. Studios, clubs and trainers pay for group tools.'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.workspace_premium_outlined, color: SoColors.amber),
            title: const Text('Credits & licences'),
            subtitle: const Text('Where the 1,400 exercises come from'),
            trailing: const Icon(Icons.chevron_right, color: SoColors.muted),
            onTap: () => context.push('/credits'),
          ),
          const SizedBox(height: 16),
          const SectionTitle('Account'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(auth != null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: auth != null ? SoColors.mint : SoColors.muted),
            title: Text(auth != null ? 'Signed in' : BackendConfig.enabled ? 'Not signed in' : 'Demo build, no backend'),
            subtitle: Text(auth != null
                ? auth.email ?? auth.id
                : BackendConfig.enabled
                    ? 'Sign in to sync and use the cloud coach'
                    : 'Pass SUPABASE_URL and SUPABASE_KEY at build time'),
            trailing: BackendConfig.enabled
                ? TextButton(
                    onPressed: () async {
                      if (auth != null) {
                        await signOut();
                        if (context.mounted) toast(context, 'Signed out. Your data stays on this device.');
                      } else {
                        context.push('/signin');
                      }
                    },
                    child: Text(auth != null ? 'Sign out' : 'Sign in'),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          const SectionTitle('Trust and video'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.verified_outlined, color: ref.watch(profileProvider)?.creator == true ? SoColors.mint : SoColors.muted),
            title: Text(ref.watch(profileProvider)?.creator == true ? 'Creator: uploads open' : 'Not a creator yet'),
            subtitle: Text(ref.watch(profileProvider)?.creator == true
                ? 'Clips up to 60 s, screened automatically, streamed via Cloudflare Stream or Mux'
                : 'Video uploads open to approved creators first. Apply from Creator studio.'),
            trailing: TextButton(onPressed: () => context.push('/studio'), child: const Text('Studio')),
          ),
          if (ref.watch(isModeratorProvider))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.shield_outlined, color: SoColors.violet),
              title: const Text('Moderation queue'),
              subtitle: Text(auth != null ? 'You hold the moderator flag' : 'Demo build: everyone can review the seeded reports'),
              trailing: TextButton(onPressed: () => context.push('/moderation'), child: const Text('Open')),
            ),
          const SizedBox(height: 16),
          const SectionTitle('AI coach'),
          Text(
            auth != null
                ? 'Signed in: the Ritmo cloud coach answers (Claude via our backend, key never leaves the server, 5 free messages a week). The key below is only used when signed out.'
                : 'The coach runs on Claude (${settings.model}). Paste an Anthropic API key to enable it on this device. '
                    'Without a key the offline rule-based coach answers instead.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _key,
            obscureText: !_show,
            decoration: InputDecoration(
              hintText: 'sk-ant-…',
              suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _show = !_show)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () async {
                  await ref.read(settingsProvider.notifier).setApiKey(_key.text);
                  if (context.mounted) toast(context, _key.text.trim().isEmpty ? 'Key removed, offline coach active' : 'Claude coach enabled');
                },
                child: const Text('Save key'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  _key.clear();
                  await ref.read(settingsProvider.notifier).setApiKey('');
                },
                child: const Text('Remove'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: SoColors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(
              'Demo mode: the key is stored on this device and calls the API directly. The production app never ships keys; '
              'requests go through the Ritmo backend which holds the key and enforces per-user quotas.',
              style: t.bodySmall?.copyWith(color: SoColors.amber),
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Data'),
          Text('Open-source exercise data: free-exercise-db (Unlicense) bundled offline, wger.de (AGPL / CC-BY-SA) fetched live.', style: t.bodySmall),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Reset Ritmo?'),
                  content: const Text('Deletes your profile, routines, posts and settings on this device.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reset', style: TextStyle(color: SoColors.coral))),
                  ],
                ),
              );
              if (ok == true) {
                await ref.read(profileProvider.notifier).reset();
                ref.invalidate(routinesProvider);
                ref.invalidate(socialProvider);
                ref.invalidate(settingsProvider);
                ref.invalidate(coachProvider);
                if (context.mounted) context.go('/onboarding');
              }
            },
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset app data'),
          ),
          const SizedBox(height: 24),
          Center(child: Text('Ritmo 0.2.0 · social graph', style: t.bodySmall)),
        ],
      ),
    );
  }
}
