import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'lobby_screen.dart';
import 'login_screen.dart'; // Ensure this exists

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _joinController = TextEditingController();
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final Random _rng = Random();
  bool _isLoading = false;

  @override
  void dispose() {
    _joinController.dispose();
    super.dispose();
  }

  // --- LOGIC: CREATE ROOM ---
  void _createRoom() async {
    setState(() => _isLoading = true);

    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    String roomCode = List.generate(
      4,
      (index) => chars[_rng.nextInt(chars.length)],
    ).join();

    try {
      await FirebaseFirestore.instance.collection('rooms').doc(roomCode).set({
        'host_id': currentUser!.uid,
        'status': 'lobby',
        'created_at': FieldValue.serverTimestamp(),
        'players': [
          {
            'uid': currentUser!.uid,
            'email': currentUser!.email,
            'score': 0,
            'is_host': true,
          },
        ],
        'settings': {
          'rounds': 5,
          'types': {'trivia': true, 'true_false': true, 'one_word': true},
        },
      });

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LobbyScreen(roomCode: roomCode, isHost: true),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- LOGIC: JOIN ROOM ---
  void _joinRoom() async {
    String code = _joinController.text.toUpperCase().trim();
    if (code.length != 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Code must be 4 letters")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final roomRef = FirebaseFirestore.instance.collection('rooms').doc(code);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(roomRef);

        if (!snapshot.exists) throw Exception("Room not found!");

        List players = snapshot.get('players');
        bool alreadyIn = players.any((p) => p['uid'] == currentUser!.uid);

        if (!alreadyIn) {
          if (players.length >= 8) throw Exception("Room is full!");

          transaction.update(roomRef, {
            'players': FieldValue.arrayUnion([
              {
                'uid': currentUser!.uid,
                'email': currentUser!.email,
                'score': 0,
                'is_host': false,
              },
            ]),
          });
        }
      });

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LobbyScreen(roomCode: code, isHost: false),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- LOGIC: ADD FRIEND ---
  void _addFriend() {
    TextEditingController friendEmailController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Friend"),
        content: TextField(
          controller: friendEmailController,
          decoration: const InputDecoration(hintText: "Enter friend's email"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("Friend Added!")));
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  // --- UI: DRAWER ---
  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.redAccent),
            accountName: const Text(
              "Player",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(currentUser?.email ?? "No Email"),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                currentUser?.email?.substring(0, 1).toUpperCase() ?? "P",
                style: const TextStyle(fontSize: 40.0, color: Colors.redAccent),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.people, color: Colors.redAccent),
            title: const Text('Add Friend'),
            subtitle: const Text('Coming Soon'),
            onTap: () {
              Navigator.pop(context);
              _addFriend();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.grey),
            title: const Text('Logout'),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Quiz Rooms",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.redAccent,
        elevation: 0,
      ),
      drawer: _buildDrawer(),
      // 🟢 LAYOUT BUILDER: Prevents '1 pixel' overflows
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            // This makes sure the container is AT LEAST the size of the screen,
            // but can grow bigger if needed (scrolling).
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.redAccent.withOpacity(0.1), Colors.white],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isLoading)
                          const LinearProgressIndicator(
                            color: Colors.redAccent,
                          ),
                        const SizedBox(height: 20),

                        // --- CREATE ROOM CARD ---
                        Card(
                          elevation: 8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          color: Colors.redAccent,
                          child: InkWell(
                            onTap: _isLoading ? null : _createRoom,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 40,
                                horizontal: 20,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.add_circle_outline,
                                    size: 40,
                                    color: Colors.white,
                                  ),
                                  SizedBox(height: 10),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      "CREATE ROOM",
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),

                        const Row(
                          children: [
                            Expanded(child: Divider(thickness: 2)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                "OR",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(thickness: 2)),
                          ],
                        ),

                        const SizedBox(height: 40),

                        // --- JOIN ROOM SECTION ---
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              children: [
                                const Text(
                                  "Have a code?",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _joinController,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 32,
                                    letterSpacing: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: "ABCD",
                                    hintStyle: TextStyle(
                                      color: Colors.grey.withOpacity(0.5),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: const BorderSide(
                                        color: Colors.redAccent,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      side: const BorderSide(
                                        color: Colors.redAccent,
                                        width: 2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: _isLoading ? null : _joinRoom,
                                    child: const Text(
                                      "JOIN ROOM",
                                      style: TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
