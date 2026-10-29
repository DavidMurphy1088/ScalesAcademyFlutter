import 'package:flutter/material.dart';

import 'common.dart';
import 'listen_page.dart';
import 'score_test_page.dart';
import 'sound_test_page.dart';

/// Start screen: the test screens built so far, one per stage
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: saAppBar(context, 'SA Flutter'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _entry(context, Icons.mic, 'Listen', 'Microphone pitch detection and SA scoring (Stage 0)', const ListenPage()),
          _entry(context, Icons.music_note, 'Sound', 'Piano notes, scales and metronome (Stage 1)', const SoundTestPage()),
          _entry(context, Icons.library_music, 'Score', 'Scales drawn as SA draws them, with the playing note ringed (Stage 2)',
              const ScoreTestPage()),
        ],
      ),
    );
  }

  Widget _entry(BuildContext context, IconData icon, String title, String subtitle, Widget page) => Card(
        child: ListTile(
          leading: Icon(icon, size: 32),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
        ),
      );
}
