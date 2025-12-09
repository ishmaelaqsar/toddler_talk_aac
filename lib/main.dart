import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const MyVoiceApp());
}

class MyVoiceApp extends StatelessWidget {
  const MyVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Voice AAC',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
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

  // State Variables
  List<Map<String, dynamic>> sentenceStrip = [];
  List<Map<String, dynamic>> customCards = [];
  bool isEditMode = false;

  // Core Vocabulary - High frequency words
  final List<Map<String, dynamic>> coreWords = [
    {"id": "core_1", "label": "I", "color": 0xFFFFF59D, "icon": "🙂"},
    {"id": "core_2", "label": "Want", "color": 0xFFA5D6A7, "icon": "🤲"},
    {"id": "core_3", "label": "Stop", "color": 0xFFEF9A9A, "icon": "🛑"},
    {"id": "core_4", "label": "Yes", "color": 0xFFC5E1A5, "icon": "👍"},
    {"id": "core_5", "label": "No", "color": 0xFFFFCC80, "icon": "👎"},
    {"id": "core_6", "label": "Help", "color": 0xFF90CAF9, "icon": "🆘"},
    {"id": "core_7", "label": "Go", "color": 0xFF80CBC4, "icon": "🏃"},
    {"id": "core_8", "label": "More", "color": 0xFFCE93D8, "icon": "➕"},
  ];

  @override
  void initState() {
    super.initState();
    _initTTS();
    _loadCustomCards();
  }

  // Initialize Text-to-Speech engine
  void _initTTS() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.4);
    await flutterTts.setPitch(1.0);
  }

  // Load custom cards from local storage
  Future<void> _loadCustomCards() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedData = prefs.getString('custom_cards');
    if (storedData != null) {
      setState(() {
        customCards = List<Map<String, dynamic>>.from(json.decode(storedData));
      });
    }
  }

  // Save custom cards to local storage
  Future<void> _saveCustomCards() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('custom_cards', json.encode(customCards));
  }

  // Add a word to the top sentence strip and speak it
  void _addToStrip(Map<String, dynamic> card) {
    setState(() {
      sentenceStrip.add(card);
    });
    flutterTts.speak(card['label']);
  }

  // Read the entire sentence strip aloud
  void _playSentence() {
    String sentence = sentenceStrip.map((e) => e['label']).join(" ");
    flutterTts.speak(sentence);
  }

  void _clearStrip() {
    setState(() => sentenceStrip.clear());
  }

  // Logic to take a photo and create a new card
  Future<void> _addNewCard() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
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
      });
    });
    _saveCustomCards();
  }

  Future<void> _deleteCustomCard(int index) async {
    setState(() {
      customCards.removeAt(index);
    });
    _saveCustomCards();
  }

  Future<String?> _showLabelDialog() {
    TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Name this card"),
        content: TextField(controller: controller, autofocus: true),
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

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder provides the screen constraints for responsive design
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTablet = constraints.maxWidth > 600;

        final int gridColumns = isTablet ? 4 : 2;
        final double stripHeight = isTablet ? 140 : 100;
        final double iconSize = isTablet ? 40 : 30;
        final double textSize = isTablet ? 22 : 16;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              "My Voice",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                icon: Icon(isEditMode ? Icons.edit_off : Icons.edit),
                onPressed: () => setState(() => isEditMode = !isEditMode),
                tooltip: "Toggle Edit Mode",
              ),
            ],
          ),
          body: Column(
            children: [
              // 1. Sentence Strip
              Container(
                height: stripHeight,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: sentenceStrip.length,
                        itemBuilder: (context, index) {
                          return _buildSmallCard(
                            sentenceStrip[index],
                            isTablet,
                          );
                        },
                      ),
                    ),
                    const VerticalDivider(),
                    FloatingActionButton(
                      heroTag: "play",
                      onPressed: sentenceStrip.isEmpty ? null : _playSentence,
                      backgroundColor: Colors.green,
                      mini: !isTablet,
                      child: const Icon(Icons.volume_up),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton(
                      heroTag: "clear",
                      onPressed: _clearStrip,
                      backgroundColor: Colors.redAccent,
                      mini: true,
                      child: const Icon(Icons.backspace),
                    ),
                  ],
                ),
              ),

              // 2. Vocabulary Grid
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: GridView(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridColumns,
                      childAspectRatio: 1.1,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    children: [
                      ...coreWords.map(
                        (word) => _buildCoreCard(word, iconSize, textSize),
                      ),
                      ...customCards.asMap().entries.map(
                        (entry) =>
                            _buildCustomCard(entry.value, entry.key, textSize),
                      ),
                      if (isEditMode) _buildAddButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCoreCard(
    Map<String, dynamic> data,
    double iconSize,
    double textSize,
  ) {
    return GestureDetector(
      onTap: () => _addToStrip(data),
      child: Container(
        decoration: BoxDecoration(
          color: Color(data['color']),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.black12, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(data['icon'], style: TextStyle(fontSize: iconSize)),
            const SizedBox(height: 5),
            Text(
              data['label'],
              style: TextStyle(fontSize: textSize, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomCard(
    Map<String, dynamic> data,
    int index,
    double textSize,
  ) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () => _addToStrip(data),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.blueAccent, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Image.file(
                        File(data['imagePath']),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                Text(
                  data['label'],
                  style: TextStyle(
                    fontSize: textSize * 0.9,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
              ],
            ),
          ),
        ),
        if (isEditMode)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              color: Colors.white54,
              child: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                onPressed: () => _deleteCustomCard(index),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSmallCard(Map<String, dynamic> data, bool isTablet) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      elevation: 2,
      child: Container(
        width: isTablet ? 100 : 70,
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (data.containsKey('imagePath'))
              Expanded(child: Image.file(File(data['imagePath'])))
            else
              Text(
                data['icon'] ?? "",
                style: TextStyle(fontSize: isTablet ? 30 : 20),
              ),

            Text(
              data['label'],
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isTablet ? 14 : 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _addNewCard,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: Colors.grey,
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.camera_alt, size: 40, color: Colors.grey),
              Text(
                "Add Photo",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
