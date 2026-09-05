import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

/// Comment thread under a post (v0.2). Works against the local seed and the
/// hosted graph alike through the social provider.
class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({super.key, required this.post});
  final Post post;

  static Future<void> show(BuildContext context, Post post) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => CommentsSheet(post: post),
      );

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(socialProvider.notifier).loadComments(widget.post.id));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    await ref.read(socialProvider.notifier).addComment(widget.post.id, text);
    _input.clear();
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final social = ref.watch(socialProvider);
    final thread = social.comments[widget.post.id];
    final notifier = ref.read(socialProvider.notifier);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  Expanded(child: Text('Comments', style: t.titleLarge)),
                  Text(compact(social.posts.where((p) => p.id == widget.post.id).firstOrNull?.comments ?? widget.post.comments), style: t.bodySmall),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: thread == null
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : thread.isEmpty
                      ? const EmptyState(emoji: '💬', title: 'No comments yet', body: 'Say something useful, or at least kind.')
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                          itemCount: thread.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 14),
                          itemBuilder: (_, i) {
                            final c = thread[i];
                            final u = notifier.userOf(c.authorId);
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Avatar(u.emoji, size: 32),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Text(u.name, style: t.titleSmall),
                                        const SizedBox(width: 6),
                                        Text('@${u.handle} · ${timeAgo(c.createdAt)}', style: t.bodySmall),
                                      ]),
                                      const SizedBox(height: 2),
                                      Text(c.body, style: t.bodyMedium),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        onSubmitted: (_) => _send(),
                        textInputAction: TextInputAction.send,
                        maxLength: 1000,
                        decoration: const InputDecoration(hintText: 'Add a comment…', counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      style: IconButton.styleFrom(backgroundColor: SoColors.coral, foregroundColor: Colors.white),
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
