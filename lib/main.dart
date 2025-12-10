import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart'; // For Zipping
import 'package:file_picker/file_picker.dart'; // For Import
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p; // For filename manipulation
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart'; // For Exporting
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const ToddlerTalkApp());
}

class ToddlerTalkApp extends StatelessWidget {
  const ToddlerTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Toddler Talk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF81D4FA)),
        scaffoldBackgroundColor: const Color(0xFFFFFDE7),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FlutterTts flutterTts = FlutterTts();
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> customCards = [];
  bool isAdminMode = false;

  // Track which card is currently being touched for visual feedback
  String? _activeCardId;

  // TODDLER CORE VOCABULARY
  final List<Map<String, dynamic>> coreWords = [
    {"id": "c1", "label": "Hungry", "color": 0xFFFFCC80, "icon": "🍎"},
    {"id": "c2", "label": "Thirsty", "color": 0xFF81D4FA, "icon": "🥤"},
    {"id": "c3", "label": "Play", "color": 0xFFA5D6A7, "icon": "🧸"},
    {"id": "c4", "label": "Sleep", "color": 0xFFCE93D8, "icon": "💤"},
    {"id": "c5", "label": "Yes", "color": 0xFFC5E1A5, "icon": "👍"},
    {"id": "c6", "label": "No", "color": 0xFFEF9A9A, "icon": "👎"},
    {"id": "c7", "label": "More", "color": 0xFFFFF59D, "icon": "➕"},
    {"id": "c8", "label": "All Done", "color": 0xFFB0BEC5, "icon": "🙅"},
  ];

  @override
  void initState() {
    super.initState();
    _initTTS();
    _loadCustomCards();
  }

  void _initTTS() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
  }

  Future<void> _loadCustomCards() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedData = prefs.getString('toddler_cards');
    if (storedData != null) {
      setState(() {
        customCards = List<Map<String, dynamic>>.from(json.decode(storedData));
      });
    }
  }

  Future<void> _saveCustomCards() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('toddler_cards', json.encode(customCards));
  }

  // --- BACKUP & RESTORE LOGIC ---

  Future<void> _backupData() async {
    if (customCards.isEmpty) {
      _speak("Nothing to backup");
      return;
    }

    try {
      final archive = Archive();
      final appDir = await getApplicationDocumentsDirectory();
      List<Map<String, dynamic>> portableList = [];

      for (var card in customCards) {
        final File imageFile = File(card['imagePath']);
        final String filename = p.basename(card['imagePath']);

        if (await imageFile.exists()) {
          final List<int> bytes = await imageFile.readAsBytes();
          archive.addFile(ArchiveFile(filename, bytes.length, bytes));

          Map<String, dynamic> portableCard = Map.from(card);
          portableCard['imagePath'] = filename;
          portableList.add(portableCard);
        }
      }

      final String jsonStr = jsonEncode(portableList);
      archive.addFile(
        ArchiveFile('data.json', jsonStr.length, utf8.encode(jsonStr)),
      );

      final ZipEncoder encoder = ZipEncoder();
      final File zipFile = File('${appDir.path}/toddler_talk_backup.zip');

      await zipFile.writeAsBytes(encoder.encode(archive));

      await SharePlus.instance.share(
        ShareParams(text: 'Toddler Talk Backup', files: [XFile(zipFile.path)]),
      );
    } catch (e) {
      _speak("Backup failed");
      debugPrint("Backup Error: $e");
    }
  }

  Future<void> _restoreData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result == null) return;

      final File zipFile = File(result.files.single.path!);
      final appDir = await getApplicationDocumentsDirectory();

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      List<Map<String, dynamic>> importedCards = [];

      // 1. Unzip Files
      for (final file in archive) {
        if (file.isFile) {
          final data = file.content as List<int>;
          if (file.name == 'data.json') {
            String jsonStr = utf8.decode(data);
            List<dynamic> jsonList = jsonDecode(jsonStr);
            importedCards = List<Map<String, dynamic>>.from(jsonList);
          } else {
            // Check if we already have this image to avoid duplicates
            File outFile = File('${appDir.path}/${file.name}');
            if (!await outFile.exists()) {
              await outFile.create(recursive: true);
              await outFile.writeAsBytes(data);
            }
          }
        }
      }

      // 2. Fix Paths
      for (var card in importedCards) {
        card['imagePath'] = '${appDir.path}/${card['imagePath']}';
      }

      // 3. MERGE LOGIC: Add only if ID doesn't exist
      int addedCount = 0;
      setState(() {
        for (var newCard in importedCards) {
          // Check if a card with this ID already exists
          final bool exists = customCards.any((c) => c['id'] == newCard['id']);
          if (!exists) {
            customCards.add(newCard);
            addedCount++;
          }
        }
      });

      _saveCustomCards();
      _speak(addedCount > 0 ? "Added $addedCount items" : "No new items found");
    } catch (e) {
      _speak("Restore failed");
      debugPrint("Restore Error: $e");
    }
  }

  // --- ACTIONS ---

  void _speak(String text) {
    flutterTts.speak(text);
  }

  void _handleCardTap(String id, String label) {
    setState(() => _activeCardId = id);
    _speak(label);

    // Visual reset after animation
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _activeCardId = null);
    });
  }

  Future<void> _addNewCard() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 800, // Limit size for performance/backup
      maxHeight: 800,
      imageQuality: 85,
    );

    if (photo == null) return;

    final directory = await getApplicationDocumentsDirectory();
    final String path = '${directory.path}/${const Uuid().v4()}.jpg';
    await photo.saveTo(path);

    if (!mounted) return;
    String? label = await _showLabelDialog();
    if (label == null || label.isEmpty) return;

    setState(() {
      customCards.add({
        "id": const Uuid().v4(),
        "label": label,
        "imagePath": path,
        "isCustom": true,
        "isVisible": true,
      });
    });
    _saveCustomCards();
  }

  Future<void> _deleteCard(int index) async {
    setState(() => customCards.removeAt(index));
    _saveCustomCards();
  }

  void _toggleVisibility(int index) {
    setState(() {
      bool current = customCards[index]['isVisible'] ?? true;
      customCards[index]['isVisible'] = !current;
    });
    _saveCustomCards();
  }

  Future<String?> _showLabelDialog() {
    TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("What is this?"),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTablet = constraints.maxWidth > 600;
        final int gridColumns = isTablet ? 3 : 2;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: isAdminMode
                ? const Text("Mom Mode", style: TextStyle(color: Colors.red))
                : const Text("Toddler Talk"),
            actions: [
              if (isAdminMode)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'backup') _backupData();
                    if (value == 'restore') _restoreData();
                  },
                  itemBuilder: (BuildContext context) {
                    return [
                      const PopupMenuItem(
                        value: 'backup',
                        child: Text('Backup Data'),
                      ),
                      const PopupMenuItem(
                        value: 'restore',
                        child: Text('Restore/Merge Data'),
                      ),
                    ];
                  },
                  icon: const Icon(Icons.settings, color: Colors.black),
                ),
              GestureDetector(
                onLongPress: () {
                  setState(() => isAdminMode = !isAdminMode);
                  _speak(isAdminMode ? "Editing Mode On" : "Locked");
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Icon(
                    isAdminMode ? Icons.lock_open : Icons.lock,
                    color: isAdminMode ? Colors.red : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: GridView(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: gridColumns,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  children: [
                    ...coreWords.map((word) => _buildCard(word)),
                    // Filter hidden cards UNLESS we are in Admin Mode
                    ...customCards
                        .asMap()
                        .entries
                        .where(
                          (e) => isAdminMode || (e.value['isVisible'] ?? true),
                        )
                        .map((e) => _buildCustomCard(e.value, e.key)),
                    if (isAdminMode) _buildAddButton(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard(Map<String, dynamic> data) {
    final bool isActive = _activeCardId == data['id'];

    return GestureDetector(
      onTapDown: (_) => setState(() => _activeCardId = data['id']),
      onTapUp: (_) => _handleCardTap(data['id'], data['label']),
      onTapCancel: () => setState(() => _activeCardId = null),
      child: AnimatedScale(
        scale: isActive ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            color: Color(data['color']),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(data['icon'], style: const TextStyle(fontSize: 60)),
              const SizedBox(height: 8),
              Text(
                data['label'],
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomCard(Map<String, dynamic> data, int index) {
    final bool isActive = _activeCardId == data['id'];
    final bool isVisible = data['isVisible'] ?? true;

    return Stack(
      children: [
        GestureDetector(
          onTapDown: (_) => setState(() => _activeCardId = data['id']),
          onTapUp: (_) => _handleCardTap(data['id'], data['label']),
          onTapCancel: () => setState(() => _activeCardId = null),
          child: AnimatedScale(
            scale: isActive ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: Container(
              // Dim the card if it is "Hidden" in Admin Mode
              foregroundDecoration: (isAdminMode && !isVisible)
                  ? BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(24),
                    )
                  : null,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.blue.shade100, width: 4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(data['imagePath']), fit: BoxFit.cover),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.8),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          data['label'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isAdminMode) ...[
          // DELETE BUTTON
          Positioned(
            right: 0,
            top: 0,
            child: FloatingActionButton.small(
              heroTag: "del_$index",
              backgroundColor: Colors.red,
              onPressed: () => _deleteCard(index),
              child: const Icon(Icons.close, color: Colors.white),
            ),
          ),
          // HIDE/SHOW TOGGLE BUTTON
          Positioned(
            left: 0,
            top: 0,
            child: FloatingActionButton.small(
              heroTag: "hide_$index",
              backgroundColor: isVisible ? Colors.blue : Colors.grey,
              onPressed: () => _toggleVisibility(index),
              child: Icon(
                isVisible ? Icons.visibility : Icons.visibility_off,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _addNewCard,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade400, width: 2),
        ),
        child: const Center(
          child: Icon(Icons.add_a_photo, size: 50, color: Colors.grey),
        ),
      ),
    );
  }
}
