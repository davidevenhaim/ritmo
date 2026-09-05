import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'nocturne.dart';
import '../features/home/start_sheet.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/breathe/breathe_screen.dart';
import '../features/coach/coach_screen.dart';
import '../features/creator/creator_profile_screen.dart';
import '../features/creator/studio_screen.dart';
import '../features/moderation/moderation_screen.dart';
import '../features/explore/exercise_detail_screen.dart';
import '../features/explore/explore_screen.dart';
import '../features/feed/feed_screen.dart';
import '../features/build/build_screen.dart';
import '../features/community/community_screen.dart';
import '../features/build/session_builder_screen.dart';
import '../core/session_theme.dart';
import '../features/friends/friends_screen.dart';
import '../features/home/calendar_screen.dart';
import '../features/home/me_screen.dart';
import '../features/home/schedule_screen.dart';
import '../features/leagues/league_detail_screen.dart';
import '../features/leagues/leagues_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/credits_screen.dart';
import '../features/profile/settings_screen.dart';
import '../features/routines/routine_preview_screen.dart';
import '../features/routines/workout_player_screen.dart';
import '../features/steps/steps_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final hasProfile = ref.watch(profileProvider.select((p) => p != null));
  return GoRouter(
    initialLocation: hasProfile ? '/home' : '/onboarding',
    redirect: (context, state) {
      final onboarding = state.matchedLocation == '/onboarding';
      if (!hasProfile && !onboarding) return '/onboarding';
      if (hasProfile && onboarding) return '/home';
      // Old deep links from v0.4/v0.5 still land somewhere sensible.
      if (state.matchedLocation == '/me') return '/home';
      if (state.matchedLocation == '/feed') return '/friends';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Shell(shell: shell),
        // v0.9: the handoff's own bar — Me, the raised Start button, and
        // Community. Building a routine is what Start opens, not a tab;
        // Friends sits at the top of Me. Everything else (coach, steps,
        // discover, exercise library, breathing, leagues, settings) is one
        // tap from these two tabs.
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const MeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/community', builder: (_, _) => const CommunityScreen())]),
        ],
      ),
      GoRoute(path: '/friends', builder: (_, _) => const FriendsScreen()),
      GoRoute(path: '/build', builder: (_, _) => const BuildScreen()),
      GoRoute(
        path: '/exercise/:id',
        builder: (_, s) => ExerciseDetailScreen(exerciseId: s.pathParameters['id']!, exercise: s.extra as Exercise?),
      ),
      // Look inside a routine somebody shared before accepting it (v0.10).
      GoRoute(
        path: '/routine/:id',
        builder: (_, s) => RoutinePreviewScreen(
          routineId: s.pathParameters['id']!,
          routine: s.extra as Routine?,
          focusDay: int.tryParse(s.uri.queryParameters['day'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/workout/:id',
        builder: (_, s) => WorkoutPlayerScreen(
          routineId: s.pathParameters['id']!,
          routine: s.extra as Routine?,
          initialDay: int.tryParse(s.uri.queryParameters['day'] ?? '') ?? 0,
        ),
      ),
      GoRoute(path: '/me', builder: (_, _) => const MeScreen()),
      GoRoute(path: '/calendar', builder: (_, _) => const CalendarScreen()),
      GoRoute(path: '/schedule', builder: (_, _) => const ScheduleScreen()),
      GoRoute(path: '/steps', builder: (_, _) => const StepsScreen()),
      GoRoute(path: '/coach', builder: (_, _) => const CoachScreen()),
      GoRoute(path: '/discover', builder: (_, _) => const FeedScreen()),
      GoRoute(path: '/explore', builder: (_, _) => const ExploreScreen()),
      GoRoute(path: '/breathe', builder: (_, _) => const BreatheScreen()),
      GoRoute(
        path: '/build/:theme',
        builder: (_, s) => SessionBuilderScreen(
          theme: SessionTheme.byId(s.pathParameters['theme']!),
          draft: s.uri.queryParameters['ai'] == '1',
        ),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/credits', builder: (_, _) => const CreditsScreen()),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: '/signin', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/u/:id', builder: (_, s) => CreatorProfileScreen(userId: s.pathParameters['id']!)),
      GoRoute(path: '/studio', builder: (_, _) => const StudioScreen()),
      GoRoute(path: '/moderation', builder: (_, _) => const ModerationScreen()),
      GoRoute(path: '/leagues', builder: (_, _) => const LeaguesScreen()),
      GoRoute(
        path: '/leagues/:id',
        builder: (_, s) => LeagueDetailScreen(leagueId: s.pathParameters['id']!, league: s.extra as League?),
      ),
    ],
  );
});

class _Shell extends StatelessWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;

  /// Nocturne tab bar: icon 21px over a 9.5px label, active #e9e9ed,
  /// inactive #75798c, hairline top border, no fill behind the selection.
  /// The handoff's raised Start button sits in the middle and opens the
  /// routine picker; it is not a tab, so it never takes the selection.
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Noc.bg,
        body: shell,
        bottomNavigationBar: SizedBox(
          // 24 of the button's 58 sit above the bar, as the handoff draws it.
          height: 58 + 24 + MediaQuery.paddingOf(context).bottom,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Noc.bg,
                    border: Border(top: BorderSide(color: Noc.divider)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: 58,
                      child: Row(
                        children: [
                          Expanded(child: _Tab(icon: Nx.user, label: 'Me', index: 0, shell: shell)),
                          const SizedBox(
                            width: 84,
                            child: Align(
                              alignment: Alignment(0, 0.62),
                              child: Text(
                                'Start',
                                style: TextStyle(fontFamily: 'Inter', fontSize: 9.5, fontVariations: Noc.w500, color: Noc.accent300),
                              ),
                            ),
                          ),
                          Expanded(child: _Tab(icon: Nx.usersThree, label: 'Community', index: 1, shell: shell)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: _StartButton(key: const Key('startButton'), onTap: () => showStartSheet(context)),
                ),
              ),
            ],
          ),
        ),
      );
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.index, required this.shell});
  final IconData icon;
  final String label;
  final int index;
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final on = shell.currentIndex == index;
    return InkWell(
      onTap: () => shell.goBranch(index, initialLocation: on),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 21, color: on ? Noc.text : Noc.dim),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(fontFamily: 'Inter', fontSize: 9.5, fontVariations: Noc.w500, color: on ? Noc.text : Noc.dim),
          ),
        ],
      ),
    );
  }
}

/// Start: raised over the bar, accent fill, a play triangle. One tap from
/// anywhere in the app to the routine picker.
class _StartButton extends StatefulWidget {
  const _StartButton({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Start a workout',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? 0.94 : 1,
            duration: const Duration(milliseconds: 120),
            child: Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Flat accent-400 disc, dark glyph, a ring of the page ground
                // cutting it out of the bar, and a shadow rather than a bloom.
                color: Noc.accent400,
                border: Border.all(color: Noc.bg, width: 5),
                boxShadow: const [BoxShadow(color: Color(0x8C0F111C), blurRadius: 16, spreadRadius: 1, offset: Offset(0, 4))],
              ),
              child: const Icon(Nx.barbell, size: 24, color: Noc.accent900),
            ),
          ),
        ),
      );
}
