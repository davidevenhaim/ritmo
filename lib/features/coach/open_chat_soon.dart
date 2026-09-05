import 'package:flutter/material.dart';

import '../../app/nocturne.dart';

/// Why the coach takes questions from a list and not from a keyboard (v0.12).
///
/// The coach itself is on and free. What is not open yet is the free-text box,
/// because an open chat is what costs real money per athlete, and Ritmo does
/// not charge a trainee. So the box says Soon, and this is what it says when
/// somebody taps it — the plain reason, not a sales page.
const kOpenChatSoonTitle = 'Open questions are coming soon';
const kOpenChatSoonBody =
    'We are thinking about how to make this AI coach free for everyone — an open chat is the '
    'part that costs money for every athlete who uses it, and Ritmo is not going to charge '
    'trainees for it. The moment we have that worked out, this box opens.';
const kOpenChatSoonAside = 'The questions above are the real coach, free and on: it reads your profile and writes from the same library.';

Future<void> showOpenChatSoonSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      // The sheet draws the handoff's own handle, not the theme's Material one.
      showDragHandle: false,
      backgroundColor: Noc.sheet,
      barrierColor: Noc.scrim,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Noc.rSheet))),
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Noc.line, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Noc.accent800, borderRadius: BorderRadius.circular(Noc.rControl)),
                  child: const Icon(Nx.chatCircle, size: 19, color: Noc.accent200),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('SOON', style: Noc.kickerAccent),
                    SizedBox(height: 2),
                    Text(kOpenChatSoonTitle, style: Noc.cardTitle),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              Text(kOpenChatSoonBody, style: Noc.body.copyWith(color: Noc.muted)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(color: Noc.sunken, borderRadius: BorderRadius.circular(Noc.rControl)),
                child: Row(children: [
                  const Icon(Nx.shieldCheck, size: 15, color: Noc.accent400),
                  const SizedBox(width: 10),
                  Expanded(child: Text(kOpenChatSoonAside, style: Noc.small)),
                ]),
              ),
              const SizedBox(height: 16),
              NocButton(label: 'Got it', block: true, onTap: () => Navigator.pop(sheet)),
            ],
          ),
        ),
      ),
    );
