import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/exercise_repository.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: SoColors.coral,
          labelColor: SoColors.text,
          unselectedLabelColor: SoColors.muted,
          tabs: const [Tab(text: 'Library'), Tab(text: 'wger community · live')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [LibraryTab(), WgerTab()],
      ),
    );
  }
}

class LibraryTab extends ConsumerStatefulWidget {
  const LibraryTab({super.key, this.onPick});
  final ValueChanged<Exercise>? onPick;
  @override
  ConsumerState<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<LibraryTab> {
  final _query = TextEditingController();
  String? _muscle;
  String? _equipment;
  String? _category;
  String? _level;

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(exerciseRepoProvider);
    return repoAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(emoji: '😵', title: 'Could not load the library', body: '$e'),
      data: (repo) {
        final results = repo.search(query: _query.text, muscle: _muscle, equipment: _equipment, category: _category, level: _level, limit: 120);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search ${NumberFormat.decimalPattern().format(repo.all.length)} exercises',
                  prefixIcon: const Icon(Icons.search, color: SoColors.muted),
                  suffixIcon: _query.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_query.clear)),
                ),
              ),
            ),
            _FilterRow(
              label: 'Muscle',
              options: repo.muscles,
              value: _muscle,
              onChanged: (v) => setState(() => _muscle = v),
            ),
            _FilterRow(
              label: 'Equipment',
              options: repo.equipmentTypes,
              value: _equipment,
              onChanged: (v) => setState(() => _equipment = v),
            ),
            _FilterRow(
              label: 'Type',
              options: repo.categories,
              value: _category,
              onChanged: (v) => setState(() => _category = v),
            ),
            // Every exercise is graded, so this row never has an "unknown"
            // bucket: beginner, intermediate, advanced and nothing else.
            _FilterRow(
              label: 'Level',
              options: ExerciseLevel.catalogue,
              value: _level,
              onChanged: (v) => setState(() => _level = v),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: results.isEmpty
                  ? const EmptyState(emoji: '🔍', title: 'No exercises match', body: 'Try fewer filters.')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => ExerciseTile(
                        exercise: results[i],
                        onTap: widget.onPick != null
                            ? () => widget.onPick!(results[i])
                            : () => context.push('/exercise/${results[i].id}', extra: results[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.label, required this.options, required this.value, required this.onChanged});
  final String label;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 10),
              child: Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
            ),
            for (final o in options)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(o),
                  selected: o == value,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  onSelected: (_) => onChanged(o == value ? null : o),
                ),
              ),
          ],
        ),
      );
}

class ExerciseTile extends StatelessWidget {
  const ExerciseTile({super.key, required this.exercise, required this.onTap, this.trailing});
  final Exercise exercise;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: SoColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: SoColors.line)),
          child: Row(
            children: [
              ExerciseThumb(exercise, size: 60, animate: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise.name, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (exercise.primary.isNotEmpty) TagChip(exercise.primary.first, color: SoColors.coral),
                        TagChip(exercise.equipment, color: SoColors.amber),
                        if (exercise.level != null) TagChip(exercise.level!),
                        if (exercise.source == 'wger') const TagChip('wger', color: SoColors.violet),
                      ],
                    ),
                  ],
                ),
              ),
              trailing ?? const Icon(Icons.chevron_right, color: SoColors.muted),
            ],
          ),
        ),
      );
}

/// Live browse of the wger open-source exercise database.
class WgerTab extends ConsumerStatefulWidget {
  const WgerTab({super.key});
  @override
  ConsumerState<WgerTab> createState() => _WgerTabState();
}

class _WgerTabState extends ConsumerState<WgerTab> {
  final List<Exercise> _items = [];
  int _offset = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(wgerClientProvider).fetchPage(offset: _offset, limit: 20);
      setState(() {
        _items.addAll(page);
        _offset += 20;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: SoColors.violet.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: const Text(
            'Fresh from wger.de, the open-source workout manager. Community-maintained, CC-BY-SA content, fetched live.',
            style: TextStyle(fontSize: 13, color: SoColors.text),
          ),
        ),
        const SizedBox(height: 10),
        for (final e in _items) ...[
          ExerciseTile(exercise: e, onTap: () => context.push('/exercise/${e.id}', extra: e)),
          const SizedBox(height: 8),
        ],
        if (_error != null)
          EmptyState(emoji: '📡', title: 'wger is unreachable', body: _error, action: OutlinedButton(onPressed: _loadMore, child: const Text('Retry'))),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_error == null)
          Center(child: OutlinedButton(onPressed: _loadMore, child: const Text('Load more'))),
      ],
    );
  }
}

/// Full-screen exercise picker used by the routine builder.
Future<Exercise?> pickExercise(BuildContext context) => showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.92,
        child: LibraryTab(onPick: (e) => Navigator.of(ctx).pop(e)),
      ),
    );

extension ExerciseLookup on ExerciseRepository {
  Exercise? find(String id, Exercise? extra) => extra ?? byId(id);
}
