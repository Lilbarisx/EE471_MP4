import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoboMunch Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFE5A93C), // Gold
        scaffoldBackgroundColor: const Color(0xFF16110F), // Very deep warm brown
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE5A93C),
          secondary: Color(0xFF8D5B4C), // Terracotta/Brown
          surface: Color(0xFF251C1A), // Card warm dark
          onPrimary: Color(0xFF16110F),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: Color(0xFFF7EBE8), fontWeight: FontWeight.bold, letterSpacing: 1.2),
          bodyMedium: TextStyle(color: Color(0xFFDCD1CE)),
        ),
        useMaterial3: true,
      ),
      home: const RoboMunchStudio(),
    );
  }
}

class RoboMunchStudio extends StatefulWidget {
  const RoboMunchStudio({super.key});

  @override
  State<RoboMunchStudio> createState() => _RoboMunchStudioState();
}

class _RoboMunchStudioState extends State<RoboMunchStudio> {
  // Connection Settings (Change these using the settings icon in appbar)
  String _localBackendIp = '192.168.1.37'; // Default local IP (User can override)
  String _localBackendPort = '7860';
  String _cloudBackendIp = 'YOUR-VM-IP'; // Default cloud IP (User can override)
  String _cloudBackendPort = '8000';

  // Getters for full URLs
  String get _localUrl => 'http://$_localBackendIp:$_localBackendPort';
  String get _cloudUrl => 'http://$_cloudBackendIp:$_cloudBackendPort';

  // Controllers
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  // State Variables
  String? _generatedImageBase64;
  bool _isGeneratingImage = false;
  bool _isProcessingImage = false;
  String? _imageResolution;
  bool _isGrayscale = false;

  final List<Map<String, String>> _chatHistory = [
    {
      'role': 'assistant',
      'content': 'Hello! I am RoboMunch, your creative assistant. Type a message or use voice command to talk to me!'
    }
  ];
  bool _isChatLoading = false;

  // Speech to Text variables
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastWords = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onStatus: (status) {
          debugPrint('STT Status: $status');
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (errorNotification) {
          debugPrint('STT Error: $errorNotification');
          setState(() => _isListening = false);
          _showErrorSnackbar('Speech recognition error: ${errorNotification.errorMsg}');
        },
      );
      setState(() {});
    } catch (e) {
      debugPrint('STT Init Exception: $e');
    }
  }

  void _startListening() async {
    await _speechToText.listen(
      onResult: (result) {
        setState(() {
          _lastWords = result.recognizedWords;
          _chatController.text = _lastWords;
        });
      },
    );
    setState(() {
      _isListening = true;
    });
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _isListening = false;
    });
  }

  // API Call: Local LLM Chat
  Future<void> _sendChatMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _chatHistory.add({'role': 'user', 'content': text});
      _chatController.clear();
      _isChatLoading = true;
    });
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse('$_localUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': text}),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _chatHistory.add({'role': 'assistant', 'content': data['response']});
        });
      } else {
        _showErrorSnackbar('Local backend error: Status ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackbar('Failed to connect to Local Backend at $_localUrl');
    } finally {
      setState(() {
        _isChatLoading = false;
      });
      _scrollToBottom();
    }
  }

  // API Call: Local Image Generation (Stable Diffusion)
  Future<void> _generateImage() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _showErrorSnackbar('Please write a prompt first!');
      return;
    }

    setState(() {
      _isGeneratingImage = true;
      _imageResolution = null;
      _isGrayscale = false;
    });

    try {
      final response = await http.post(
        Uri.parse('$_localUrl/generate_image'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      ).timeout(const Duration(seconds: 60)); // Long timeout for local SD generation

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _generatedImageBase64 = data['image'];
        });
      } else {
        _showErrorSnackbar('Image generation failed: Status ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackbar('Failed to connect to Local Backend at $_localUrl');
    } finally {
      setState(() {
        _isGeneratingImage = false;
      });
    }
  }

  // API Call: Cloud Grayscale Conversion + Resolution Info
  Future<void> _processImageCloud() async {
    if (_generatedImageBase64 == null) {
      _showErrorSnackbar('Generate an image in the Art Studio first!');
      return;
    }

    setState(() {
      _isProcessingImage = true;
    });

    final imageBytes = base64Decode(_generatedImageBase64!);

    try {
      // 1. Get Image Resolution from Cloud Backend
      var resRequest = http.MultipartRequest('POST', Uri.parse('$_cloudUrl/get/resolution'));
      resRequest.files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'image.png',
      ));

      final resResponse = await resRequest.send();
      if (resResponse.statusCode == 200) {
        final resDataString = await resResponse.stream.bytesToString();
        final resData = jsonDecode(resDataString);
        setState(() {
          _imageResolution = resData['resolution'] ?? "${resData['width']}x${resData['height']}";
        });
      } else {
        debugPrint('Cloud Resolution endpoint error: Status ${resResponse.statusCode}');
      }

      // 2. Get Grayscale Image from Cloud Backend
      var grayRequest = http.MultipartRequest('POST', Uri.parse('$_cloudUrl/convert/grayscale'));
      grayRequest.files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'image.png',
      ));
      // Ask for base64 JSON response format
      grayRequest.fields['response_format'] = 'json';

      final grayResponse = await grayRequest.send();
      if (grayResponse.statusCode == 200) {
        final grayDataString = await grayResponse.stream.bytesToString();
        final grayData = jsonDecode(grayDataString);
        setState(() {
          _generatedImageBase64 = grayData['image'];
          _isGrayscale = true;
        });
        _showSuccessSnackbar('Image converted to grayscale successfully!');
      } else {
        _showErrorSnackbar('Grayscale conversion error: Status ${grayResponse.statusCode}');
      }

    } catch (e) {
      _showErrorSnackbar('Failed to connect to Cloud Backend at $_cloudUrl');
    } finally {
      setState(() {
        _isProcessingImage = false;
      });
    }
  }

  // Helper: scroll chat to bottom
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Helpers for snackbars
  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.black)),
        backgroundColor: const Color(0xFFE5A93C),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Settings Panel for IPs
  void _openSettingsDialog() {
    final localIpController = TextEditingController(text: _localBackendIp);
    final localPortController = TextEditingController(text: _localBackendPort);
    final cloudIpController = TextEditingController(text: _cloudBackendIp);
    final cloudPortController = TextEditingController(text: _cloudBackendPort);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF251C1A),
          title: const Row(
            children: [
              Icon(Icons.settings, color: Color(0xFFE5A93C)),
              SizedBox(width: 10),
              Text('Connection Settings', style: TextStyle(color: Color(0xFFF7EBE8))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Set Local Backend (Server 1) details:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE5A93C)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: localIpController,
                        decoration: const InputDecoration(
                          labelText: 'Local Host IP',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: localPortController,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Set Cloud Backend (Server 2) details:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE5A93C)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: cloudIpController,
                        decoration: const InputDecoration(
                          labelText: 'VM Cloud IP',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: cloudPortController,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE5A93C),
                foregroundColor: const Color(0xFF16110F),
              ),
              onPressed: () {
                setState(() {
                  _localBackendIp = localIpController.text.trim();
                  _localBackendPort = localPortController.text.trim();
                  _cloudBackendIp = cloudIpController.text.trim();
                  _cloudBackendPort = cloudPortController.text.trim();
                });
                Navigator.pop(context);
                _showSuccessSnackbar('Backend paths updated successfully!');
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.orientation == Orientation.portrait;

    Widget buildArtStudio() {
      return Card(
        color: const Color(0xFF251C1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF3E302C), width: 1.5),
        ),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Art Studio',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE5A93C),
                    ),
                  ),
                  if (_imageResolution != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x4D8D5B4C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF8D5B4C), width: 1),
                      ),
                      child: Text(
                        'Res: $_imageResolution',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFF7EBE8), fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Image Box
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF16110F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF3E302C), width: 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_generatedImageBase64 != null)
                        Image.memory(
                          base64Decode(_generatedImageBase64!),
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                        )
                      else if (_isGeneratingImage)
                        const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Color(0xFFE5A93C)),
                            SizedBox(height: 12),
                            Text('Munch is painting...', style: TextStyle(color: Color(0xFFE5A93C), fontStyle: FontStyle.italic)),
                          ],
                        )
                      else
                        const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.palette_outlined, size: 48, color: Color(0xFF5A4945)),
                            SizedBox(height: 8),
                            Text(
                              'Generated artwork will show up here',
                              style: TextStyle(color: Color(0xFF5A4945), fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      if (_isProcessingImage)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(color: Color(0xFFE5A93C)),
                                SizedBox(height: 12),
                                Text('Processing in the cloud...', style: TextStyle(color: Color(0xFFF7EBE8))),
                              ],
                            ),
                          ),
                        ),
                      if (_generatedImageBase64 != null && _isGrayscale)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE5A93C), width: 1),
                            ),
                            child: const Text(
                              'GRAYSCALE',
                              style: TextStyle(
                                color: Color(0xFFE5A93C),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Prompt Input Box
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      style: const TextStyle(color: Color(0xFFF7EBE8)),
                      decoration: InputDecoration(
                        hintText: 'Type your prompt here.',
                        hintStyle: const TextStyle(color: Color(0xFF5A4945)),
                        filled: true,
                        fillColor: const Color(0xFF16110F),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Color(0xFF3E302C)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Color(0xFF3E302C)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Color(0xFFE5A93C)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Paint button
                  InkWell(
                    onTap: _isGeneratingImage || _isProcessingImage ? null : _generateImage,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE5A93C),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.brush,
                        color: Color(0xFF16110F),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Colorize Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _generatedImageBase64 != null ? const Color(0xFF8D5B4C) : const Color(0xFF3E302C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  disabledBackgroundColor: const Color(0xFF3E302C),
                ),
                onPressed: _generatedImageBase64 == null || _isGeneratingImage || _isProcessingImage
                    ? null
                    : _processImageCloud,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.color_lens_outlined),
                    SizedBox(width: 8),
                    Text(
                      'colorize',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.0),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildChatStudio() {
      return Card(
        color: const Color(0xFF251C1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF3E302C), width: 1.5),
        ),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Chat Studio',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE5A93C),
                ),
              ),
              const SizedBox(height: 12),
              // Chat Log Output Box
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16110F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF3E302C), width: 1),
                  ),
                  child: ListView.builder(
                    controller: _chatScrollController,
                    itemCount: _chatHistory.length + (_isChatLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _chatHistory.length) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF251C1A),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE5A93C)),
                            ),
                          ),
                        );
                      }

                      final message = _chatHistory[index];
                      final isUser = message['role'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                          decoration: BoxDecoration(
                            color: isUser ? const Color(0xFF8D5B4C) : const Color(0xFF251C1A),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
                              bottomRight: isUser ? Radius.zero : const Radius.circular(16),
                            ),
                            border: Border.all(
                              color: isUser ? const Color(0xFFA56D5E) : const Color(0xFF3E302C),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isUser ? 'YOU' : 'MUNCH',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isUser ? Colors.white70 : const Color(0xFFE5A93C),
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                message['content'] ?? '',
                                style: const TextStyle(color: Color(0xFFF7EBE8), fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Chat Input & Voice Controls
              Row(
                children: [
                  // Microphone Voice Button
                  InkWell(
                    onTap: _speechEnabled
                        ? (_isListening ? _stopListening : _startListening)
                        : null,
                    borderRadius: BorderRadius.circular(30),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isListening ? Colors.redAccent : const Color(0xFF251C1A),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isListening ? Colors.red : const Color(0xFF3E302C),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.white : const Color(0xFFE5A93C),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Message Text Field
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      style: const TextStyle(color: Color(0xFFF7EBE8)),
                      decoration: InputDecoration(
                        hintText: _isListening ? 'Listening...' : 'Type your message here.',
                        hintStyle: const TextStyle(color: Color(0xFF5A4945)),
                        filled: true,
                        fillColor: const Color(0xFF16110F),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Color(0xFF3E302C)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Color(0xFF3E302C)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Color(0xFFE5A93C)),
                        ),
                      ),
                      onSubmitted: (_) => _sendChatMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send message button
                  InkWell(
                    onTap: _isChatLoading ? null : _sendChatMessage,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE5A93C),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send,
                        color: Color(0xFF16110F),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1715),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Color(0xFFE5A93C),
                shape: BoxShape.circle,
              ),
              child: const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF251C1A),
                child: Icon(Icons.person, color: Color(0xFFE5A93C)), // Placeholder avatar
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ROBO MUNCH',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE5A93C),
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  'Art & Chat Studio',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFFE5A93C)),
            onPressed: _openSettingsDialog,
            tooltip: 'Connection Settings',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E1715),
              Color(0xFF16110F),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: isPortrait
              ? Column(
                  children: [
                    Expanded(flex: 11, child: buildArtStudio()),
                    const SizedBox(height: 8),
                    Expanded(flex: 12, child: buildChatStudio()),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: buildArtStudio()),
                    const SizedBox(width: 12),
                    Expanded(child: buildChatStudio()),
                  ],
                ),
        ),
      ),
    );
  }
}
