import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'game_screen.dart';

class LobbyScreen extends StatefulWidget {
  final String roomCode;
  final bool isHost;

  const LobbyScreen({super.key, required this.roomCode, required this.isHost});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final currentUser = FirebaseAuth.instance.currentUser;

  // --- LOGIC: LEAVE ROOM ---
  void _leaveRoom() async {
    try {
      final roomRef = FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomCode);
      final snapshot = await roomRef.get();
      if (!snapshot.exists) return;

      List players = snapshot.get('players');
      List newPlayers = players
          .where((p) => p['uid'] != currentUser!.uid)
          .toList();

      if (newPlayers.isEmpty) {
        await roomRef.delete();
      } else {
        await roomRef.update({'players': newPlayers});
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      print("Error leaving room: $e");
    }
  }

  // --- LOGIC: UPDATE SETTINGS (Host Only) ---
  void _showSettingsDialog(Map<String, dynamic> currentSettings) {
    // Local state variables for the dialog
    int rounds = currentSettings['rounds'] ?? 5;
    bool trivia = currentSettings['types']['trivia'] ?? true;
    bool trueFalse = currentSettings['types']['true_false'] ?? true;
    bool oneWord = currentSettings['types']['one_word'] ?? true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Game Settings"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. ROUNDS SELECTOR
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Rounds:",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      DropdownButton<int>(
                        value: rounds,
                        items: [3, 5, 10, 15, 20]
                            .map(
                              (e) =>
                                  DropdownMenuItem(value: e, child: Text("$e")),
                            )
                            .toList(),
                        onChanged: (val) => setDialogState(() => rounds = val!),
                      ),
                    ],
                  ),
                  const Divider(),
                  const Text(
                    "Question Types",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),

                  // 2. TOGGLES
                  SwitchListTile(
                    title: const Text("Trivia / MCQ"),
                    value: trivia,
                    activeColor: Colors.redAccent,
                    onChanged: (val) => setDialogState(() => trivia = val),
                  ),
                  SwitchListTile(
                    title: const Text("True or False"),
                    value: trueFalse,
                    activeColor: Colors.redAccent,
                    onChanged: (val) => setDialogState(() => trueFalse = val),
                  ),
                  SwitchListTile(
                    title: const Text("One Word (Hint)"),
                    value: oneWord,
                    activeColor: Colors.redAccent,
                    onChanged: (val) => setDialogState(() => oneWord = val),
                  ),

                  // Error Message if none selected
                  if (!trivia && !trueFalse && !oneWord)
                    const Text(
                      "Select at least one type!",
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                  onPressed: (!trivia && !trueFalse && !oneWord)
                      ? null // Disable save if nothing selected
                      : () async {
                          // SAVE TO FIREBASE
                          await FirebaseFirestore.instance
                              .collection('rooms')
                              .doc(widget.roomCode)
                              .update({
                                'settings': {
                                  'rounds': rounds,
                                  'types': {
                                    'trivia': trivia,
                                    'true_false': trueFalse,
                                    'one_word': oneWord,
                                  },
                                },
                              });
                          if (mounted) Navigator.pop(context);
                        },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- LOGIC: START GAME ---
  // Inside _LobbyScreenState
  void _startGame() async {
    // 1. Update status so everyone knows game started
    await FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomCode)
        .update({'status': 'starting'});

    // 2. Navigation is handled by the StreamBuilder in the Build method!
    // See step below...
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomCode)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        if (!snapshot.data!.exists)
          return const Scaffold(body: Center(child: Text("Room ended.")));

        var roomData = snapshot.data!.data() as Map<String, dynamic>;
        List players = roomData['players'] ?? [];
        Map<String, dynamic> settings =
            roomData['settings'] ??
            {
              'rounds': 5,
              'types': {'trivia': true},
            };

        String status = roomData['status'] ?? 'lobby';

        if (status == 'starting') {
          // We use postFrameCallback to avoid navigation errors during the build phase
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => GameScreen(
                  roomCode: widget.roomCode,
                  isHost: widget.isHost,
                  settings: settings,
                ),
              ),
            );
          });
        }
        // Helper text for settings display
        List<String> activeTypes = [];
        if (settings['types']['trivia'] == true) activeTypes.add("Trivia");
        if (settings['types']['true_false'] == true) activeTypes.add("T/F");
        if (settings['types']['one_word'] == true) activeTypes.add("One Word");

        return Scaffold(
          appBar: AppBar(
            title: const Text("Lobby"),
            backgroundColor: Colors.redAccent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _leaveRoom,
            ),
            actions: [
              // SETTINGS ICON (HOST ONLY)
              if (widget.isHost)
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () => _showSettingsDialog(settings),
                ),
            ],
          ),
          body: Column(
            children: [
              // --- HEADER: ROOM INFO ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                ),
                child: Column(
                  children: [
                    Text(
                      "ROOM CODE: ${widget.roomCode}",
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Display Current Settings to Everyone
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        Chip(
                          label: Text("${settings['rounds']} Rounds"),
                          backgroundColor: Colors.white,
                        ),
                        ...activeTypes.map(
                          (t) => Chip(
                            label: Text(t),
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // --- PLAYER LIST ---
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    var player = players[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.redAccent,
                          child: Text(
                            player['email'].substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(player['email'].split('@')[0]),
                        trailing: player['is_host'] == true
                            ? const Icon(Icons.star, color: Colors.orange)
                            : null,
                      ),
                    );
                  },
                ),
              ),

              // --- START BUTTON ---
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: widget.isHost
                    ? SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                          ),
                          // 1. Disable button if only 1 player
                          onPressed: players.length > 1 ? _startGame : null,

                          // 2. Change Text based on player count
                          child: Text(
                            players.length > 1
                                ? "START GAME (${players.length}/8)"
                                : "WAITING FOR PLAYERS...",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                    : const Text(
                        "Waiting for host...",
                        style: TextStyle(color: Colors.grey),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
