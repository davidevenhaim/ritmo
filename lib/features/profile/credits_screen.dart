import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';

/// Required attributions for the bundled exercise catalogue (v0.6). Every
/// source below is credited because its licence asks for it; do not remove
/// an entry without removing its data from `assets/data/exercises.json`.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  static const _sources = [
    (
      'RepDB',
      'repdb.co',
      'https://repdb.co',
      'Exercise data by RepDB. 484 illustrated exercises including cardio machines, mobility and stretching. Free tier licence: commercial use allowed with this credit; the data may not be redistributed as a dataset.',
    ),
    (
      'free-exercise-db',
      'github.com/yuhonas/free-exercise-db',
      'https://github.com/yuhonas/free-exercise-db',
      '876 exercises with photos, released into the public domain under the Unlicense.',
    ),
    (
      'Ritmo editorial',
      'written in-house',
      '',
      '36 exercises written by us to fill the ends of the ladder: supported and kneeling regressions for people starting out, long-lever and single-leg work for people who are not.',
    ),
    (
      'Yoga API',
      'github.com/alexcumplido/yoga-api',
      'https://github.com/alexcumplido/yoga-api',
      'Yoga poses with Sanskrit names, descriptions and benefits, by Alexandre C. under the MIT licence.',
    ),
    (
      'Yoga icons: monkik',
      'flaticon.com/authors/monkik',
      'https://www.flaticon.com/authors/monkik',
      'Easy icons created by monkik — Flaticon.',
    ),
    (
      'Yoga icons: dDara',
      'flaticon.com/authors/ddara',
      'https://www.flaticon.com/authors/ddara',
      'Yoga icons created by dDara — Flaticon.',
    ),
    (
      'wger',
      'wger.de',
      'https://wger.de',
      'Community exercise database browsed live from the Explore tab. Content is CC-BY-SA.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Credits & licences')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(
            'Ritmo is free for everyone. The exercise library is built from open sources, and each one is credited here as its licence requires.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (final (name, host, url, blurb) in _sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: SoColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: SoColors.line)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: t.titleMedium),
                    const SizedBox(height: 2),
                    // Our own rows have nothing to link to.
                    if (url.isEmpty)
                      Text(host, style: t.bodySmall)
                    else
                      InkWell(
                        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                        child: Text(host, style: t.bodySmall?.copyWith(color: SoColors.coral, decoration: TextDecoration.underline)),
                      ),
                    const SizedBox(height: 6),
                    Text(blurb, style: t.bodySmall),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Step counts come from Apple Health or Health Connect and are read-only. The AI trainer runs on Claude by Anthropic.',
            style: t.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
