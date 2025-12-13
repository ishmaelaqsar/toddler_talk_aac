import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:giphy_get/giphy_get.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
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
  final AudioPlayer audioPlayer = AudioPlayer();
  final ImagePicker _picker = ImagePicker();

  final String giphyApiKey = dotenv.env['GIPHY_API_KEY'] ?? "";

  List<Map<String, dynamic>> allCards = [];
  bool isAdminMode = false;
  String? _activeCardId;

  final List<Map<String, dynamic>> defaultCards = [
    {
      "label": "Hungry",
      "color": 0xFFFFCC80,
      "type": "asset",
      "content": "assets/symbols/dinner.svg",
    },
    {
      "label": "Thirsty",
      "color": 0xFF81D4FA,
      "type": "asset",
      "content": "assets/symbols/water.svg",
    },
    {
      "label": "Play",
      "color": 0xFFA5D6A7,
      "type": "asset",
      "content": "assets/symbols/lego.svg",
    },
  ];

  @override
  void initState() {
    super.initState();
    _initTTS();
    _loadCards();
  }

  void _initTTS() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
  }

  Future<void> _loadCards() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedData = prefs.getString('toddler_cards_v5');

    if (storedData != null) {
      setState(() {
        allCards = List<Map<String, dynamic>>.from(json.decode(storedData));
      });
    } else {
      setState(() {
        allCards = defaultCards.map((c) {
          return {
            "id": const Uuid().v4(),
            "label": c['label'],
            "color": c['color'],
            "type": c['type'],
            "content": c['content'],
            "audioPath": null,
            "isVisible": true,
          };
        }).toList();
      });
      _saveCards();
    }
  }

  Future<void> _saveCards() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('toddler_cards_v5', json.encode(allCards));
  }

  Future<void> _handleCardTap(Map<String, dynamic> card) async {
    setState(() => _activeCardId = card['id']);

    if (card['audioPath'] != null && File(card['audioPath']).existsSync()) {
      await audioPlayer.play(DeviceFileSource(card['audioPath']));
    } else {
      flutterTts.speak(card['label']);
    }

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _activeCardId = null);
    });
  }

  // --- BACKUP & RESTORE ---

  Future<void> _backupData() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final encoder = ZipFileEncoder();
      final zipPath = '${directory.path}/toddler_talk_backup.zip';

      // 1. Create a temporary JSON file for card data
      final dataFile = File('${directory.path}/cards.json');
      await dataFile.writeAsString(json.encode(allCards));

      // 2. Create Zip
      encoder.create(zipPath);
      encoder.addFile(dataFile);

      // 3. Add all custom images/audio found in the app directory
      List<FileSystemEntity> files = directory.listSync();
      for (var file in files) {
        if (file is File) {
          final ext = p.extension(file.path);
          if (['.jpg', '.png', '.m4a', '.gif'].contains(ext)) {
            encoder.addFile(file);
          }
        }
      }
      encoder.close();

      // 4. Share the file
      await SharePlus.instance.share(
        ShareParams(files: [XFile(zipPath)], text: 'Toddler Talk Backup'),
      );
    } catch (e) {
      debugPrint("Backup Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Backup Failed")));
      }
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
      final directory = await getApplicationDocumentsDirectory();

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          File('${directory.path}/$filename')
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        }
      }

      final dataFile = File('${directory.path}/cards.json');
      if (await dataFile.exists()) {
        final String data = await dataFile.readAsString();
        setState(() {
          allCards = List<Map<String, dynamic>>.from(json.decode(data));
        });
        _saveCards();

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Restore Successful!")));
        }
      }
    } catch (e) {
      debugPrint("Restore Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Restore Failed")));
      }
    }
  }

  // --- ACTIONS: ADD NEW CARD ---

  Future<void> _addNewCard() async {
    final String? source = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Create Card From..."),
        children: [
          ListTile(
            leading: const Icon(Icons.gif_box, color: Colors.purple),
            title: const Text("Giphy Search"),
            subtitle: const Text("Search animated GIFs"),
            onTap: () => Navigator.pop(ctx, 'giphy'),
          ),
          ListTile(
            leading: const Icon(Icons.grid_view, color: Colors.orange),
            title: const Text("Symbol Library"),
            onTap: () => Navigator.pop(ctx, 'library'),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.blue),
            title: const Text("Take Photo"),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Colors.green),
            title: const Text("Photo Gallery"),
            subtitle: const Text("Supports GIFs"),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
        ],
      ),
    );

    if (source == null) return;
    if (!mounted) return;

    String? content;
    String type = 'image';
    String initialLabel = "";

    if (source == 'giphy') {
      if (giphyApiKey == "YOUR_GIPHY_API_KEY_HERE" || giphyApiKey.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Please set your Giphy API Key in .env file first!",
              ),
            ),
          );
        }
        return;
      }

      GiphyGif? gif = await GiphyGet.getGif(
        context: context,
        apiKey: giphyApiKey,
        tabColor: Colors.teal,
      );

      final String? gifUrl = gif?.images?.original?.url;

      if (gifUrl != null) {
        final String? localPath = await _downloadFile(gifUrl);
        if (localPath == null) return;

        content = localPath;
        type = 'image';
        initialLabel = gif?.title?.split("GIF")[0].trim() ?? "Gif";
      } else {
        return;
      }
    } else if (source == 'library') {
      final String? selectedPath = await _pickSymbolFromAssets();
      if (selectedPath == null) return;

      content = selectedPath;
      type = 'asset';
      initialLabel = p
          .basenameWithoutExtension(selectedPath)
          .replaceAll('_', ' ')
          .replaceAll('-', ' ');
    } else {
      if (source == 'camera') {
        if (await Permission.camera.request().isDenied) {
          return;
        }
      }

      final XFile? photo = await _picker.pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      );
      if (photo == null) return;

      final directory = await getApplicationDocumentsDirectory();
      final String ext = p.extension(photo.path);
      final String path = '${directory.path}/${const Uuid().v4()}$ext';

      await photo.saveTo(path);
      content = path;
      type = 'image';
    }

    if (!mounted) return;

    if (initialLabel.isNotEmpty && initialLabel.length > 1) {
      initialLabel = initialLabel[0].toUpperCase() + initialLabel.substring(1);
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CardEditorDialog(initialLabel: initialLabel),
    );

    if (result == null) return;

    setState(() {
      allCards.add({
        "id": const Uuid().v4(),
        "label": result['label'],
        "type": type,
        "content": content,
        "audioPath": result['audioPath'],
        "color": 0xFFFFFFFF,
        "isVisible": true,
      });
    });
    _saveCards();
  }

  // --- HELPER: DOWNLOAD FILE ---
  Future<String?> _downloadFile(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final String path = '${directory.path}/${const Uuid().v4()}.gif';
        final File file = File(path);
        await file.writeAsBytes(response.bodyBytes);
        return path;
      }
    } catch (e) {
      debugPrint("Download error: $e");
    }
    return null;
  }

  Future<String?> _pickSymbolFromAssets() async {
    final AssetManifest assetManifest = await AssetManifest.loadFromAssetBundle(
      rootBundle,
    );
    final List<String> symbols = assetManifest
        .listAssets()
        .where(
          (key) => key.startsWith('assets/symbols/') && key.endsWith('.svg'),
        )
        .toList();

    if (!mounted) return null;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Choose a Symbol (${symbols.length})",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: symbols.isEmpty
                    ? const Center(
                        child: Text("No symbols found in assets/symbols/"),
                      )
                    : GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                        itemCount: symbols.length,
                        itemBuilder: (context, index) {
                          final path = symbols[index];
                          final name = p.basenameWithoutExtension(path);
                          return GestureDetector(
                            onTap: () => Navigator.pop(ctx, path),
                            child: Column(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: SvgPicture.asset(path),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- UI CONSTRUCTION ---
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int gridColumns = constraints.maxWidth > 600 ? 3 : 2;

        return Scaffold(
          appBar: AppBar(
            title: isAdminMode
                ? const Text(
                    "Mom Mode (Edit)",
                    style: TextStyle(color: Colors.red),
                  )
                : const Text("Toddler Talk"),
            actions: [
              if (isAdminMode) ...[
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'backup') {
                      _backupData();
                    }
                    if (value == 'restore') {
                      _restoreData();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'backup',
                      child: Text("Backup Data"),
                    ),
                    const PopupMenuItem(
                      value: 'restore',
                      child: Text("Restore Data"),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add_circle,
                    size: 32,
                    color: Colors.blue,
                  ),
                  onPressed: _addNewCard,
                ),
              ],
              GestureDetector(
                onLongPress: () {
                  setState(() => isAdminMode = !isAdminMode);
                  if (isAdminMode) flutterTts.speak("Editing Mode");
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
          body: ReorderableGridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridColumns,
              childAspectRatio: 1.0,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: allCards.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                final item = allCards.removeAt(oldIndex);
                allCards.insert(newIndex, item);
              });
              _saveCards();
            },
            dragWidgetBuilderV2: DragWidgetBuilderV2(
              builder: (index, child, screenshot) {
                return isAdminMode ? child : const SizedBox.shrink();
              },
            ),
            itemBuilder: (context, index) {
              final card = allCards[index];
              return Container(
                key: ValueKey(card['id']),
                child: _buildCardWidget(card, index),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCardWidget(Map<String, dynamic> card, int index) {
    Widget contentWidget;

    if (card['type'] == 'asset') {
      contentWidget = Padding(
        padding: const EdgeInsets.all(16.0),
        child: SvgPicture.asset(
          card['content'],
          fit: BoxFit.contain,
          placeholderBuilder: (_) =>
              const Icon(Icons.broken_image, size: 50, color: Colors.grey),
        ),
      );
    } else if (card['type'] == 'image') {
      // Image.file supports Animated GIFs natively!
      contentWidget = Image.file(
        File(card['content']),
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) =>
            const Icon(Icons.error, color: Colors.red),
      );
    } else {
      contentWidget = Center(
        child: Text(card['content'], style: const TextStyle(fontSize: 70)),
      );
    }

    final double scale = (_activeCardId == card['id']) ? 0.95 : 1.0;

    return Stack(
      children: [
        GestureDetector(
          onTapDown: isAdminMode
              ? null
              : (_) => setState(() => _activeCardId = card['id']),
          onTapUp: isAdminMode ? null : (_) => _handleCardTap(card),
          onTapCancel: () => setState(() => _activeCardId = null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            transform: Matrix4.diagonal3Values(scale, scale, 1.0),
            decoration: BoxDecoration(
              color: Color(card['color'] ?? 0xFFFFFFFF),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.blue.shade100,
                width: isAdminMode ? 4 : 0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: contentWidget),
                  Expanded(
                    flex: 1,
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.9),
                      alignment: Alignment.center,
                      child: Text(
                        card['label'],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isAdminMode)
          Positioned(
            right: 0,
            top: 0,
            child: IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red),
              onPressed: () {
                setState(() => allCards.removeAt(index));
                _saveCards();
              },
            ),
          ),
      ],
    );
  }
}

class _CardEditorDialog extends StatefulWidget {
  final String initialLabel;

  const _CardEditorDialog({required this.initialLabel});

  @override
  State<_CardEditorDialog> createState() => _CardEditorDialogState();
}

class _CardEditorDialogState extends State<_CardEditorDialog> {
  late TextEditingController _textController;
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _recordedPath;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialLabel);
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _recordedPath = path;
      });
    } else {
      if (await Permission.microphone.request().isGranted) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/${const Uuid().v4()}.m4a';
        try {
          await _audioRecorder.start(const RecordConfig(), path: path);
          setState(() => _isRecording = true);
        } catch (e) {
          debugPrint("Rec Error: $e");
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Edit Card Details"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _textController,
            decoration: const InputDecoration(labelText: "Label"),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _toggleRecording,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isRecording
                    ? Colors.red
                    : (_recordedPath != null ? Colors.green : Colors.grey[300]),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isRecording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
          if (_recordedPath != null)
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text("Recording Saved!"),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () {
            if (_textController.text.isEmpty) return;
            Navigator.pop(context, {
              'label': _textController.text,
              'audioPath': _recordedPath,
            });
          },
          child: const Text("Save"),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _textController.dispose();
    super.dispose();
  }
}
