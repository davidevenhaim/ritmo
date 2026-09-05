import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/backend.dart';
import 'core/local_store.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initBackend();
  final store = await LocalStore.open();
  runApp(ProviderScope(
    overrides: [storeProvider.overrideWithValue(store)],
    child: const RitmoApp(),
  ));
}

class RitmoApp extends ConsumerStatefulWidget {
  const RitmoApp({super.key});

  @override
  ConsumerState<RitmoApp> createState() => _RitmoAppState();
}

/// Re-reads the health store whenever the app comes back to the foreground so
/// leagues and streaks pick up steps walked while it was closed (v0.4).
class _RitmoAppState extends ConsumerState<RitmoApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ref.read(profileProvider) != null) {
      ref.read(stepsProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Ritmo',
      debugShowCheckedModeBanner: false,
      theme: buildRitmoTheme(),
      darkTheme: buildRitmoTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
      // Phone-width column on wide screens (web demo, tablets, desktop).
      builder: (context, child) => Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: child),
      ),
    );
  }
}
