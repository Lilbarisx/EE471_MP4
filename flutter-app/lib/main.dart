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
        fontFamily: 'serif',
        scaffoldBackgroundColor: const Color(0xFF1C110E),
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
  // Connection Settings
  String _localBackendIp = '10.0.2.2'; // Default IP for Android Emulator (User can override)
  String _localBackendPort = '7860';
  String _cloudBackendIp = '51.20.32.187'; // Default cloud IP (User can override)
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

  final List<Map<String, String>> _chatHistory = [];
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
      ).timeout(const Duration(seconds: 120));

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

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'serif', color: Colors.white)),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'serif', color: Colors.white)),
        backgroundColor: const Color(0xFFC58B45),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openSettingsDialog() {
    final localIpController = TextEditingController(text: _localBackendIp);
    final localPortController = TextEditingController(text: _localBackendPort);
    final cloudIpController = TextEditingController(text: _cloudBackendIp);
    final cloudPortController = TextEditingController(text: _cloudBackendPort);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A110A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFF4A2B21)),
          ),
          title: const Row(
            children: [
              Icon(Icons.settings, color: Color(0xFFC58B45)),
              SizedBox(width: 10),
              Text(
                'Connection Settings',
                style: TextStyle(fontFamily: 'serif', color: Colors.white),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Local Backend (Server 1) details:',
                  style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold, color: Color(0xFFD29571)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: localIpController,
                        style: const TextStyle(color: Color(0xFFD29571)),
                        decoration: const InputDecoration(
                          labelText: 'Local Host IP',
                          labelStyle: TextStyle(color: Color(0xFFC58B45)),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: localPortController,
                        style: const TextStyle(color: Color(0xFFD29571)),
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          labelStyle: TextStyle(color: Color(0xFFC58B45)),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Note: Use 10.0.2.2 for Android Emulator, or your PC\'s Wi-Fi IP for physical phones.',
                  style: TextStyle(fontFamily: 'serif', fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Cloud Backend (Server 2) details:',
                  style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold, color: Color(0xFFD29571)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: cloudIpController,
                        style: const TextStyle(color: Color(0xFFD29571)),
                        decoration: const InputDecoration(
                          labelText: 'VM Cloud IP',
                          labelStyle: TextStyle(color: Color(0xFFC58B45)),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: cloudPortController,
                        style: const TextStyle(color: Color(0xFFD29571)),
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          labelStyle: TextStyle(color: Color(0xFFC58B45)),
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
              child: const Text('Cancel', style: TextStyle(fontFamily: 'serif', color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC58B45),
                foregroundColor: Colors.white,
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
              child: const Text('Save', style: TextStyle(fontFamily: 'serif')),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1C110E),
              Color(0xFF1A0F0D),
              Color(0xFFE2A884),
            ],
            stops: [0.0, 0.2, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Header (ROBO MUNCH & Avatar)
                Padding(
                  padding: const EdgeInsets.only(top: 10.0, bottom: 10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: 30,
                            letterSpacing: 2.0,
                          ),
                          children: [
                            TextSpan(text: 'ROBO ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.normal)),
                            TextSpan(text: 'MUNCH', style: TextStyle(color: Color(0xFFC58B45), fontWeight: FontWeight.normal)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 15),
                      // Avatar
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFC58B45), width: 2),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _openSettingsDialog,
                          child: Image.asset(
                            'assets/avatar.png',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const CircleAvatar(
                                backgroundColor: Color(0xFF2A110A),
                                child: Icon(Icons.person, color: Color(0xFFC58B45)),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Settings icon next to avatar
                      IconButton(
                        icon: const Icon(Icons.settings, color: Color(0xFFC58B45), size: 18),
                        onPressed: _openSettingsDialog,
                      ),
                    ],
                  ),
                ),

                // ART STUDIO TITLE
                const Text(
                  'Art Studio',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),

                // Image Output Box
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
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
                            SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC58B45)),
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Munch is painting...',
                              style: TextStyle(
                                fontFamily: 'serif',
                                color: Color(0xFFC58B45),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        )
                      else
                        const Text(
                          'No image generated yet.',
                          style: TextStyle(
                            fontFamily: 'serif',
                            color: Color(0xFFD29571),
                            fontStyle: FontStyle.italic,
                            fontSize: 16,
                          ),
                        ),
                      if (_isProcessingImage)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC58B45)),
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Processing in the cloud...',
                                  style: TextStyle(fontFamily: 'serif', color: Colors.white),
                                ),
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
                              border: Border.all(color: const Color(0xFFC58B45), width: 1),
                            ),
                            child: const Text(
                              'GRAYSCALE',
                              style: TextStyle(
                                fontFamily: 'serif',
                                color: Color(0xFFC58B45),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      if (_imageResolution != null)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFC58B45), width: 1),
                            ),
                            child: Text(
                              _imageResolution!,
                              style: const TextStyle(
                                fontFamily: 'serif',
                                color: Color(0xFFD29571),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Prompt Input Box Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF2A110A), Color(0xFF1A0A06)],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFF4A2B21), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _promptController,
                          style: const TextStyle(fontFamily: 'serif', color: Color(0xFFD29571), fontStyle: FontStyle.italic, fontSize: 16),
                          decoration: const InputDecoration(
                            hintText: 'Type your prompt here.',
                            hintStyle: TextStyle(color: Color(0x99D29571), fontStyle: FontStyle.italic),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _isGeneratingImage || _isProcessingImage ? null : _generateImage,
                        child: Container(
                          width: 42,
                          height: 42,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFC58B45), width: 1),
                            color: Colors.transparent,
                          ),
                          child: Image.asset(
                            'assets/paint.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.brush,
                              color: Color(0xFFC58B45),
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Colorize Button
                GestureDetector(
                  onTap: _generatedImageBase64 == null || _isGeneratingImage || _isProcessingImage
                      ? null
                      : _processImageCloud,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      gradient: _generatedImageBase64 != null
                          ? const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF2A110A), Color(0xFF1A0A06)],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF1C110E), Color(0xFF1C110E)],
                            ),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: _generatedImageBase64 != null ? const Color(0xFF4A2B21) : Colors.white12,
                        width: 1,
                      ),
                      boxShadow: _generatedImageBase64 != null
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : [],
                    ),
                    child: Text(
                      'colorize',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'serif',
                        color: _generatedImageBase64 != null ? Colors.white : Colors.white24,
                        fontSize: 16,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                // CHAT STUDIO TITLE
                const Text(
                  'Chat Studio',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),

                // Chat Log Output Box
                Container(
                  width: double.infinity,
                  height: 170,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF2A110A), Color(0xFF1A0A06)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF4A2B21), width: 1),
                  ),
                  child: ListView.builder(
                    controller: _chatScrollController,
                    itemCount: _chatHistory.length + (_isChatLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _chatHistory.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFFC58B45).withValues(alpha: 0.8)),
                              ),
                            ),
                          ),
                        );
                      }

                      final message = _chatHistory[index];
                      final isUser = message['role'] == 'user';
                      final senderLabel = isUser ? 'YOU' : 'MUNCH';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontFamily: 'serif',
                              fontSize: 15,
                              height: 1.4,
                            ),
                            children: [
                              TextSpan(
                                text: '$senderLabel: ',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              TextSpan(
                                text: message['content'] ?? '',
                                style: const TextStyle(
                                  color: Color(0xFFD29571),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 15),

                // Chat Input & Voice Row (Separate Mic and Input Box)
                Row(
                  children: [
                    // Voice Mic Button (separate circle on the left)
                    GestureDetector(
                      onTap: () {
                        if (!_speechEnabled) {
                          _initSpeech();
                          _showErrorSnackbar('Voice recognition is initializing or not supported. Check microphone permissions.');
                        } else {
                          if (_isListening) {
                            _stopListening();
                          } else {
                            _startListening();
                          }
                        }
                      },
                      child: Container(
                        width: 45,
                        height: 45,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isListening ? Colors.red : const Color(0xFFC58B45),
                            width: 1,
                          ),
                          color: _isListening ? Colors.red.withValues(alpha: 0.2) : Colors.transparent,
                        ),
                        child: Image.asset(
                          'assets/Mic.png',
                          color: _isListening ? Colors.red : null,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            color: _isListening ? Colors.red : const Color(0xFFC58B45),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Chat Input Container (Pill-shaped with Textfield & Send Button inside)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 2.0),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF2A110A), Color(0xFF1A0A06)],
                          ),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: const Color(0xFF4A2B21), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _chatController,
                                style: const TextStyle(fontFamily: 'serif', color: Color(0xFFD29571), fontStyle: FontStyle.italic, fontSize: 16),
                                decoration: InputDecoration(
                                  hintText: _isListening ? 'Listening...' : 'Type your message here.',
                                  hintStyle: const TextStyle(color: Color(0x99D29571), fontStyle: FontStyle.italic),
                                  border: InputBorder.none,
                                ),
                                onSubmitted: (_) => _sendChatMessage(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Send message button (circular button inside the pill)
                            GestureDetector(
                              onTap: _isChatLoading ? null : _sendChatMessage,
                              child: Container(
                                width: 42,
                                height: 42,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFFC58B45), width: 1),
                                  color: Colors.transparent,
                                ),
                                child: Image.asset(
                                  'assets/Send.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => const Icon(
                                    Icons.send,
                                    color: Color(0xFFC58B45),
                                    size: 18,
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
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
