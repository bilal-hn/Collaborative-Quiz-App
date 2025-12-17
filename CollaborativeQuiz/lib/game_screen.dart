import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:math';
import 'lobby_screen.dart';

class GameScreen extends StatefulWidget {
  final String roomCode;
  final bool isHost;
  final Map<String, dynamic> settings;

  const GameScreen({
    super.key,
    required this.roomCode,
    required this.isHost,
    required this.settings,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final currentUser = FirebaseAuth.instance.currentUser;

  // Question Creation Controllers
  final TextEditingController _qController = TextEditingController();
  final TextEditingController _aController = TextEditingController();

  // MCQ Controllers
  final TextEditingController _option1Controller = TextEditingController();
  final TextEditingController _option2Controller = TextEditingController();
  final TextEditingController _option3Controller = TextEditingController();
  final TextEditingController _option4Controller = TextEditingController();

  int _selectedOptionIndex = 0; // 0, 1, 2, or 3
  String? _selectedAnswer; // Tracks the answer selected by the user

  // Tracks locally which questions the user has already answered this round
  final Set<String> _answeredQuestionIds = {};

  // True/False Variable
  bool _isTrue = true; // Default to True

  // Timer State
  Stopwatch _stopwatch = Stopwatch();
  Timer? _timerTicker;

  @override
  void initState() {
    super.initState();
    if (widget.isHost) _initializeRound();
  }

  @override
  void dispose() {
    _option1Controller.dispose();
    _option2Controller.dispose();
    _option3Controller.dispose();
    _option4Controller.dispose();
    _qController.dispose();
    _aController.dispose();
    _timerTicker?.cancel();
    super.dispose();
  }

  // --- LOGIC: INITIALIZE ROUND (Host Only) ---
  void _initializeRound() async {
    // 1. Pick Random Question Type based on Settings
    List<String> enabledTypes = [];
    if (widget.settings['types']['trivia'] == true) enabledTypes.add('trivia');
    if (widget.settings['types']['true_false'] == true)
      enabledTypes.add('true_false');
    if (widget.settings['types']['one_word'] == true)
      enabledTypes.add('one_word');

    // Fallback if nothing selected
    if (enabledTypes.isEmpty) enabledTypes.add('trivia');

    String randomType = enabledTypes[Random().nextInt(enabledTypes.length)];

    // 2. Create Game State Doc
    await FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomCode)
        .collection('game')
        .doc('current_round')
        .set({
          'phase': 'creation',
          'question_type': randomType,
          'created_at': FieldValue.serverTimestamp(),
          'submissions': {},
          'round_number': 1, // Tracks who is writing vs done
        });
  }

  // --- LOGIC: END ROUND (Host Only) ---
  // --- LOGIC: END ROUND (Host Only) ---
  void _endRound() async {
    var roundRef = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomCode)
        .collection('game')
        .doc('current_round');

    // 1. Fetch Round Data (Questions & Answers)
    var roundDoc = await roundRef.get();
    var submissions = roundDoc.data()?['submissions'] as Map<String, dynamic>;
    var answerDocs = await roundRef.collection('answers').get();

    // 2. Fetch Current Player Stats
    var roomRef = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomCode);
    var roomDoc = await roomRef.get();
    List<dynamic> players = roomDoc.data()?['players'];

    // 3. GRADE ANSWERS locally
    // Map to store updates: uid -> {scoreToAdd, timeToAdd}
    Map<String, Map<String, int>> updates = {};

    for (var doc in answerDocs.docs) {
      var data = doc.data();
      String playerId = data['player_id'];
      String questionId = data['question_id'];
      String givenAnswer = data['answer'].toString().toLowerCase().trim();
      int timeTaken = data['time_taken_ms'] ?? 0;

      // Find the correct answer for this question
      var questionData = submissions[questionId];
      if (questionData == null) continue; // Should not happen

      String correctAnswer = questionData['answer']
          .toString()
          .toLowerCase()
          .trim();

      // Check if correct
      int points = (givenAnswer == correctAnswer) ? 10 : 0;

      // Accumulate stats
      if (!updates.containsKey(playerId)) {
        updates[playerId] = {'score': 0, 'time': 0};
      }
      updates[playerId]!['score'] = (updates[playerId]!['score'] ?? 0) + points;
      updates[playerId]!['time'] =
          (updates[playerId]!['time'] ?? 0) + timeTaken;
    }

    // 4. Update the Players List
    List<dynamic> updatedPlayers = players.map((p) {
      String uid = p['uid'];
      if (updates.containsKey(uid)) {
        // Add new points/time to existing ones
        int currentScore = p['score'] ?? 0;
        int currentTime = p['total_time'] ?? 0;

        // We also track 'rounds_played' to calculate average time later
        // If it's the first time adding stats, rounds_played might be 0, so we increment.
        // Since this runs once per round, we can just assume we add stats for this round.

        return {
          ...p,
          'score': currentScore + updates[uid]!['score']!,
          'total_time': currentTime + updates[uid]!['time']!,
        };
      }
      return p;
    }).toList();

    // 5. Save to Firestore & Switch Phase
    await roomRef.update({'players': updatedPlayers});

    if (roundDoc.data()?['phase'] != 'results') {
      await roundRef.update({'phase': 'results'});
    }
  }

  // --- LOGIC: START NEXT ROUND (Host Only) ---
  void _startNextRound() async {
    var roundRef = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomCode)
        .collection('game')
        .doc('current_round');

    // 🔴 NEW: Get current round number before we wipe the data
    var snapshot = await roundRef.get();
    int currentRound = snapshot.data()?['round_number'] ?? 1;
    int nextRound = currentRound + 1;

    // 1. Delete all old answers
    var answers = await roundRef.collection('answers').get();
    for (var doc in answers.docs) {
      await doc.reference.delete();
    }

    // 2. Pick new random type
    List<String> enabledTypes = [];
    if (widget.settings['types']['trivia'] == true) enabledTypes.add('trivia');
    if (widget.settings['types']['true_false'] == true)
      enabledTypes.add('true_false');
    if (widget.settings['types']['one_word'] == true)
      enabledTypes.add('one_word');
    if (enabledTypes.isEmpty) enabledTypes.add('trivia');
    String randomType = enabledTypes[Random().nextInt(enabledTypes.length)];

    // 3. Reset Round Data
    await roundRef.set({
      'phase': 'creation',
      'question_type': randomType,
      'created_at': FieldValue.serverTimestamp(),
      'submissions': {},
      'round_number': nextRound,
    });

    // 4. Clear local answered cache for the host (others update via build)
    setState(() {
      _answeredQuestionIds.clear();
    });
  }

  // --- LOGIC: SUBMIT QUESTION (Phase 1) ---
  void _submitQuestion(String type) async {
    String question = _qController.text.trim();
    String answer = "";
    List<String> options = [];

    if (question.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please enter a question!")));
      return;
    }

    // --- LOGIC BASED ON TYPE ---
    if (type == 'trivia') {
      if (_option1Controller.text.isEmpty ||
          _option2Controller.text.isEmpty ||
          _option3Controller.text.isEmpty ||
          _option4Controller.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please fill all 4 options!")),
        );
        return;
      }
      options = [
        _option1Controller.text,
        _option2Controller.text,
        _option3Controller.text,
        _option4Controller.text,
      ];
      answer = options[_selectedOptionIndex];
    } else if (type == 'true_false') {
      answer = _isTrue ? "True" : "False";
      options = ["True", "False"];
    } else if (type == 'one_word') {
      if (_aController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter the answer!")),
        );
        return;
      }
      answer = _aController.text.trim().toLowerCase(); // Normalize
    }

    // --- SAVE TO FIREBASE ---
    await FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomCode)
        .collection('game')
        .doc('current_round')
        .set({
          'submissions': {
            currentUser!.uid: {
              'status': 'submitted',
              'author_id': currentUser!.uid,
              'question': question,
              'answer': answer,
              'options': options,
              'type': type,
            },
          },
        }, SetOptions(merge: true));

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Question Submitted!")));

    setState(() {
      _qController.clear();
      _aController.clear();
      _option1Controller.clear();
      _option2Controller.clear();
      _option3Controller.clear();
      _option4Controller.clear();
      _selectedOptionIndex = 0; // Reset radio button
      _isTrue = true; // Reset True/False default
    });
  }

  // --- LOGIC: SUBMIT ANSWER (Phase 2) ---
  void _submitAnswer(String questionId, String myAnswer) async {
    _stopwatch.stop();
    _timerTicker?.cancel();

    // 1. Save to Firebase
    await FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomCode)
        .collection('game')
        .doc('current_round')
        .collection('answers')
        .add({
          'player_id': currentUser!.uid,
          'question_id': questionId,
          'answer': myAnswer,
          'time_taken_ms': _stopwatch.elapsedMilliseconds,
        });

    // 2. UI UPDATE: Mark this question as done locally!
    setState(() {
      _answeredQuestionIds.add(questionId);
      _selectedAnswer = null;
      _aController.clear();
    });
  }

  // --- MAIN BUILD METHOD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<DocumentSnapshot>(
        // 1. OUTER STREAM: Listens to GAME data (Phase, current question)
        stream: FirebaseFirestore.instance
            .collection('rooms')
            .doc(widget.roomCode)
            .collection('game')
            .doc('current_round')
            .snapshots(),
        builder: (context, gameSnapshot) {
          if (!gameSnapshot.hasData || !gameSnapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          var gameData = gameSnapshot.data!.data() as Map<String, dynamic>;
          String phase = gameData['phase'];
          String qType = gameData['question_type'];
          Map<String, dynamic> submissions = gameData['submissions'] ?? {};
          int currentRound = gameData['round_number'] ?? 1;
          int totalRounds = widget.settings['rounds'] ?? 5;

          // 2. INNER STREAM: Listens to ROOM data (Players list, Room Status)
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('rooms')
                .doc(widget.roomCode)
                .snapshots(),
            builder: (context, roomSnapshot) {
              if (!roomSnapshot.hasData) return const SizedBox();

              var roomDataFull =
                  roomSnapshot.data!.data() as Map<String, dynamic>;
              List players = roomDataFull['players'] ?? [];
              String roomStatus = roomDataFull['status'] ?? 'playing';

              // 🔴 STEP 1: CHECK FOR "BACK TO LOBBY" SIGNAL
              if (roomStatus == 'lobby') {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LobbyScreen(
                        roomCode: widget.roomCode,
                        isHost: widget.isHost,
                      ),
                    ),
                  );
                });
              }

              // 🔴 STEP 2: SHOW RESULTS SCREEN
              // (Now inside the inner stream so we can pass 'players')
              if (phase == 'results') {
                if (_answeredQuestionIds.isNotEmpty) {
                  Future.microtask(() => _answeredQuestionIds.clear());
                }
                return _buildResultsView(currentRound, totalRounds, players);
              }

              // --- HOST LOGIC: Creation -> Answering ---
              if (widget.isHost &&
                  phase == 'creation' &&
                  submissions.length == players.length) {
                FirebaseFirestore.instance
                    .collection('rooms')
                    .doc(widget.roomCode)
                    .collection('game')
                    .doc('current_round')
                    .update({'phase': 'answering'});
              }

              // --- HOST LOGIC: Answering -> Results ---
              if (widget.isHost && phase == 'answering') {
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('rooms')
                      .doc(widget.roomCode)
                      .collection('game')
                      .doc('current_round')
                      .collection('answers')
                      .snapshots(),
                  builder: (context, answerSnapshot) {
                    if (answerSnapshot.hasData) {
                      int totalPlayers = players.length;
                      // Logic: Everyone answers everyone else (N * (N-1))
                      int totalAnswersNeeded =
                          totalPlayers * (totalPlayers - 1);

                      if (totalAnswersNeeded > 0 &&
                          answerSnapshot.data!.docs.length >=
                              totalAnswersNeeded) {
                        Future.microtask(() => _endRound());
                      }
                    }
                    // Return the UI while checking
                    return _buildGameUI(phase, qType, submissions, players);
                  },
                );
              }

              // IF NOT HOST OR NOT ANSWERING PHASE, JUST SHOW UI
              return _buildGameUI(phase, qType, submissions, players);
            },
          );
        },
      ),
    );
  }

  // --- HELPER: MAIN UI WRAPPER ---
  // --- HELPER: MAIN UI WRAPPER ---
  // --- HELPER: MAIN UI WRAPPER ---
  Widget _buildGameUI(
    String phase,
    String qType,
    Map<String, dynamic> submissions,
    List players,
  ) {
    return Column(
      children: [
        // 1. GAME CONTENT (Takes all available space)
        Expanded(
          child: SingleChildScrollView(
            // Add padding so content doesn't touch edges
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
            child: phase == 'creation'
                ? _buildCreationView(qType, submissions)
                : _buildAnsweringView(submissions),
          ),
        ),

        // 2. STATUS BAR (Fixed at the bottom)
        _buildBottomStatus(submissions, players, phase),
      ],
    );
  }

  // --- VIEW: RESULTS PHASE ---
  // --- VIEW: RESULTS PHASE ---
  // 🔴 UPDATE: Now accepts round numbers
  // --- VIEW: RESULTS / GAME OVER ---
  // 🔴 UPDATE: Added 'List players' as the 3rd argument
  // --- VIEW: RESULTS / GAME OVER ---
  Widget _buildResultsView(int currentRound, int totalRounds, List players) {
    bool isLastRound = currentRound >= totalRounds;

    // 1. SORT LOGIC (Score High->Low, then Time Low->High)
    List sortedPlayers = List.from(players);
    sortedPlayers.sort((a, b) {
      int scoreA = a['score'] ?? 0;
      int scoreB = b['score'] ?? 0;

      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA); // Higher score first
      } else {
        // Tie-breaker: Lower time is better
        int timeA = a['total_time'] ?? 0;
        int timeB = b['total_time'] ?? 0;
        return timeA.compareTo(timeB);
      }
    });

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isLastRound
                  ? "🏆 FINAL RESULTS 🏆"
                  : "ROUND $currentRound STANDINGS",
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            if (isLastRound)
              const Text(
                "Winner determined by Points & Speed",
                style: TextStyle(color: Colors.grey),
              ),

            const SizedBox(height: 30),

            // LEADERBOARD CARD
            Expanded(
              // Use Expanded to handle scrolling list on small screens
              child: Card(
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Header Row
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "PLAYER",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              "SCORE (Time)",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(),

                      // Player List
                      Expanded(
                        child: ListView.builder(
                          itemCount: sortedPlayers.length,
                          itemBuilder: (context, index) {
                            var p = sortedPlayers[index];
                            int score = p['score'] ?? 0;
                            int totalTimeMs = p['total_time'] ?? 0;

                            // Calculate Average Time (Seconds)
                            // We divide by currentRound to get average per round
                            double avgTimeSec = (currentRound > 0)
                                ? (totalTimeMs / 1000) / currentRound
                                : 0.0;

                            bool isWinner = index == 0 && isLastRound;

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isWinner
                                    ? Colors.yellow[700]
                                    : Colors.redAccent,
                                child: Text(
                                  (p['email'] as String)[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                (p['email'] as String).split('@')[0],
                                style: TextStyle(
                                  fontWeight: isWinner
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 18,
                                ),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "$score pts",
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    "${avgTimeSec.toStringAsFixed(1)}s avg",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // BUTTONS
            if (widget.isHost)
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLastRound
                        ? Colors.blueAccent
                        : Colors.green,
                  ),
                  onPressed: () async {
                    if (isLastRound) {
                      // Reset Game Logic (Same as before)
                      await FirebaseFirestore.instance
                          .collection('rooms')
                          .doc(widget.roomCode)
                          .update({
                            'status': 'lobby',
                            'game': FieldValue.delete(),
                          });
                      await FirebaseFirestore.instance
                          .collection('rooms')
                          .doc(widget.roomCode)
                          .collection('game')
                          .doc('current_round')
                          .set({'round_number': 1});
                    } else {
                      _startNextRound();
                    }
                  },
                  child: Text(
                    isLastRound ? "BACK TO LOBBY" : "START NEXT ROUND",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            else
              Text(
                isLastRound
                    ? "Waiting for Host to return to lobby..."
                    : "Waiting for Host to start next round...",
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // --- VIEW: CREATION PHASE ---
  Widget _buildCreationView(String type, Map submissions) {
    bool iHaveSubmitted = submissions.containsKey(currentUser!.uid);

    if (iHaveSubmitted) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
            SizedBox(height: 20),
            Text("Waiting for others...", style: TextStyle(fontSize: 20)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Create a $type Question",
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // 1. COMMON: QUESTION INPUT
          TextField(
            controller: _qController,
            decoration: const InputDecoration(
              labelText: "Enter Question",
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 20),

          // 2. SPECIFIC INPUTS
          if (type == 'trivia') _buildTriviaInputs(),
          if (type == 'true_false') _buildTrueFalseInputs(),
          if (type == 'one_word') _buildOneWordInputs(),

          const SizedBox(height: 30),

          // 3. SUBMIT BUTTON
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.all(15),
            ),
            onPressed: () => _submitQuestion(type),
            child: const Text(
              "SUBMIT QUESTION",
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }

  // --- VIEW: ANSWERING PHASE ---
  Widget _buildAnsweringView(Map submissions) {
    // Start timer if not started
    if (!_stopwatch.isRunning) {
      _stopwatch.reset();
      _stopwatch.start();
    }

    // 1. Get questions that are NOT mine
    List questions = submissions.values.where((s) {
      String qId = s['author_id'];
      bool isMyQuestion = qId == currentUser!.uid;
      bool isAnswered = _answeredQuestionIds.contains(qId);
      return !isMyQuestion && !isAnswered;
    }).toList();

    if (questions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_bottom, size: 80, color: Colors.orangeAccent),
            SizedBox(height: 20),
            Text(
              "All caught up!",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              "Waiting for others to finish...",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // 2. Get Current Question Data
    var currentQ = questions[0];
    String type = currentQ['type'] ?? 'one_word';
    String questionText = currentQ['question'];
    String questionId = currentQ['author_id'];
    List<dynamic> options = currentQ['options'] ?? [];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "IT'S YOUR TURN!",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),

          // QUESTION CARD
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.redAccent, Colors.deepOrange],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Text(
              questionText,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 30),

          // DYNAMIC INPUT AREA
          if (type == 'trivia') _buildTriviaAnswerOptions(options),
          if (type == 'true_false') _buildTrueFalseAnswerOptions(),
          if (type == 'one_word') _buildOneWordAnswerInput(),

          const SizedBox(height: 30),

          // SUBMIT BUTTON
          SizedBox(
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 5,
              ),
              onPressed: () {
                String finalAnswer = "";

                // Determine answer based on type
                if (type == 'one_word') {
                  finalAnswer = _aController.text.trim().toLowerCase();
                } else {
                  finalAnswer = _selectedAnswer ?? "";
                }

                if (finalAnswer.isNotEmpty) {
                  _submitAnswer(questionId, finalAnswer);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please select an answer!")),
                  );
                }
              },
              child: const Text(
                "LOCK IN ANSWER",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI: FLOATING STATUS HEADER ---
  // --- UI: FLOATING STATUS HEADER (Updated) ---
  // --- UI: BOTTOM STATUS BAR ---
  Widget _buildBottomStatus(
    Map<String, dynamic> submissions,
    List players,
    String phase,
  ) {
    int questionsToAnswer = players.length - 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        // Add a subtle shadow pointing up so it looks distinct
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
        border: const Border(top: BorderSide(color: Colors.black12)),
      ),
      child: SingleChildScrollView(
        scrollDirection:
            Axis.horizontal, // 🟢 Prevents pixel overflow if many players!
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: players.map((player) {
            var uid = player['uid'];

            // --- ICON LOGIC (Same as before) ---
            Widget statusIcon;
            if (phase == 'creation') {
              var statusData = submissions[uid];
              bool isSubmitted =
                  statusData != null && statusData['status'] == 'submitted';
              statusIcon = _buildIcon(isSubmitted);
            } else {
              statusIcon = StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('rooms')
                    .doc(widget.roomCode)
                    .collection('game')
                    .doc('current_round')
                    .collection('answers')
                    .where('player_id', isEqualTo: uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return _buildIcon(false);
                  bool isDone = snapshot.data!.docs.length >= questionsToAnswer;
                  return _buildIcon(isDone);
                },
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.redAccent,
                        child: Text(
                          (player['email'] as String)[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      statusIcon,
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Show Name below bubble
                  Text(
                    (player['email'] as String).split('@')[0],
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Helper for the small check/edit icon
  Widget _buildIcon(bool isDone) {
    return CircleAvatar(
      radius: 10,
      backgroundColor: Colors.white,
      child: Icon(
        isDone ? Icons.check_circle : Icons.edit,
        size: 18,
        color: isDone ? Colors.green : Colors.orangeAccent,
      ),
    );
  }

  // --- SUB-WIDGET: TRIVIA / MCQ ---
  Widget _buildTriviaAnswerOptions(List<dynamic> options) {
    return Column(
      children: options.map((option) {
        bool isSelected = _selectedAnswer == option;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: InkWell(
            onTap: () => setState(() => _selectedAnswer = option),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.redAccent.withOpacity(0.1)
                    : Colors.white,
                border: Border.all(
                  color: isSelected ? Colors.redAccent : Colors.grey.shade300,
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: isSelected ? Colors.redAccent : Colors.grey,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // --- SUB-WIDGET: TRUE / FALSE ---
  Widget _buildTrueFalseAnswerOptions() {
    return Row(
      children: [
        Expanded(child: _buildTFButton("True", Colors.green)),
        const SizedBox(width: 15),
        Expanded(child: _buildTFButton("False", Colors.red)),
      ],
    );
  }

  Widget _buildTFButton(String label, Color color) {
    bool isSelected = _selectedAnswer == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedAnswer = label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(15),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8)]
              : [],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }

  // --- SUB-WIDGET: TRIVIA INPUTS ---
  Widget _buildTriviaInputs() {
    return Column(
      children: [
        const Text(
          "Enter 4 Options & Select the Correct One:",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Radio<int>(
                  value: i,
                  groupValue: _selectedOptionIndex,
                  activeColor: Colors.green,
                  onChanged: (val) =>
                      setState(() => _selectedOptionIndex = val!),
                ),
                Expanded(
                  child: TextField(
                    controller: [
                      _option1Controller,
                      _option2Controller,
                      _option3Controller,
                      _option4Controller,
                    ][i],
                    decoration: InputDecoration(
                      labelText: "Option ${i + 1}",
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // --- SUB-WIDGET: TRUE/FALSE INPUTS ---
  Widget _buildTrueFalseInputs() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          const Text(
            "Correct Answer:",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              const Text("True"),
              Radio<bool>(
                value: true,
                groupValue: _isTrue,
                activeColor: Colors.green,
                onChanged: (val) => setState(() => _isTrue = val!),
              ),
            ],
          ),
          Row(
            children: [
              const Text("False"),
              Radio<bool>(
                value: false,
                groupValue: _isTrue,
                activeColor: Colors.red,
                onChanged: (val) => setState(() => _isTrue = val!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- SUB-WIDGET: ONE WORD INPUT (Creation & Answer) ---
  Widget _buildOneWordInputs() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: TextField(
          controller: _aController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: "Correct Answer",
            hintText: "e.g., Paris",
            helperText: "Not case sensitive (e.g., 'paris' = 'Paris')",
            helperStyle: TextStyle(
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
            prefixIcon: const Icon(Icons.short_text, color: Colors.redAccent),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 15,
              horizontal: 10,
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () => _aController.clear(),
            ),
          ),
        ),
      ),
    );
  }

  // Reuse the same widget for Answering phase
  Widget _buildOneWordAnswerInput() {
    return _buildOneWordInputs(); // We reuse the same nice UI
  }
}
