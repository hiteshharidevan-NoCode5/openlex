import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/database/database_helper.dart';
import '../../core/tts/tts_service.dart';
import '../../core/stt/stt_service.dart';
import '../../models/word_entry.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  int _selectedIndex = -1;
  List<Map<String, dynamic>> _suggestions = [];
  WordEntry? _selectedWord;
  bool _isAdvanced = false;
  bool _isIncognito = true;
  bool _isListening = false;
  String _themeMode = 'amber'; // 'amber', 'teal', or 'wireframe'

  bool get _isWireframe => _themeMode == 'wireframe';

  Color get currentAccent {
    if (_themeMode == 'wireframe') return const Color(0xFFFFFFFF);
    if (_themeMode == 'teal') return const Color(0xFF14B8A6);
    return const Color(0xFFF59E0B);
  }

  Future<void> _loadThemePref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = prefs.getString('pref_theme_mode') ??
          (prefs.getBool('pref_teal_theme') == true ? 'teal' : 'amber');
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_themeMode == 'amber') {
        _themeMode = 'teal';
      } else if (_themeMode == 'teal') {
        _themeMode = 'wireframe';
      } else {
        _themeMode = 'amber';
      }
    });
    await prefs.setString('pref_theme_mode', _themeMode);
  }

  @override
  void initState() {
    super.initState();
    _loadThemePref();
    _searchFocusNode = FocusNode(onKeyEvent: (node, event) {
      if (_suggestions.isEmpty) return KeyEventResult.ignored;
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          setState(() {
            if (_selectedIndex < _suggestions.length - 1) {
              _selectedIndex++;
            }
          });
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(() {
            if (_selectedIndex > 0) {
              _selectedIndex--;
            } else {
              _selectedIndex = -1;
            }
          });
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.enter ||
                   event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          if (_selectedIndex >= 0 && _selectedIndex < _suggestions.length) {
            _selectWord(_suggestions[_selectedIndex]['id'], isAdvanced: _suggestions[_selectedIndex]['isAdvanced'] ?? false);
            return KeyEventResult.handled;
          }
        }
      }
      return KeyEventResult.ignored;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDeepLink();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  
  void _checkDeepLink() async {
    final uri = Uri.base;
    final query = uri.queryParameters['q'];
    if (query == null || query.trim().isEmpty) return;

    final trimmed = query.trim();
    _searchController.text = trimmed;

    final results = await DatabaseHelper.instance.searchPrefix(
      trimmed,
      
    );

    if (results.isNotEmpty && mounted) {
      final exactMatch = results.firstWhere(
        (item) => (item['word'] ?? "").toString().toLowerCase() == trimmed.toLowerCase(),
        orElse: () => results.first,
      );

      if (exactMatch.containsKey('id')) {
        _selectWord(exactMatch['id'] as int, isAdvanced: exactMatch['isAdvanced'] ?? false);
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() => _selectedIndex = -1);
    _searchDebounce?.cancel();

    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _suggestions = [];
        _selectedWord = null;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 200), () async {
      final results = await DatabaseHelper.instance.searchPrefix(trimmed);
      if (mounted && _searchController.text.trim() == trimmed) {
        setState(() {
          _suggestions = results;
        });
      }
    });
  }

  void _selectWord(int id, {bool isAdvanced = false}) async {
    final entry = await DatabaseHelper.instance.getWordDetails(
      id,
      isAdvanced: isAdvanced,
    );
    setState(() {
      _selectedWord = entry;
      _suggestions = [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDeepLink();
    });
  }

  void _setMode(bool isAdvanced) async {
    if (_isAdvanced == isAdvanced) return;

    if (isAdvanced) {
      final downloaded = await DatabaseHelper.instance.isAdvancedDownloaded();
      final needsUpdate = downloaded && await DatabaseHelper.instance.checkScholarUpdateAvailable();

      if (!downloaded || needsUpdate) {
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text(
              needsUpdate ? "Update Scholar Lexicon?" : "Download Scholar Lexicon?",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: Text(
              needsUpdate
                  ? "A new version of the 700k Scholar Lexicon is available. Would you like to update now (~70 MB)?"
                  : "Scholar mode provides 700k+ literary, medical, and comprehensive definitions (~70 MB). Stored locally for offline access.",
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(needsUpdate ? "Later" : "Cancel", style: const TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: currentAccent),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  needsUpdate ? "Update Now" : "Download (70 MB)",
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );

        if (confirm != true) {
          if (needsUpdate) {
            // Allow using the currently installed lexicon if user selects Later
          } else {
            return;
          }
        } else {
          if (needsUpdate) {
            await DatabaseHelper.instance.deleteAdvancedDatabase();
          }
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text('Download Scholar Lexicon?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: const Text(
              'Scholar mode provides 700k+ literary, medical, and comprehensive definitions (~70 MB). Stored locally for offline access.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: currentAccent),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Download (70 MB)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );

        if (confirm != true) return;

        double progress = 0.0;
        StreamSubscription<double>? sub;
        if (!mounted) return;

        final success = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => StatefulBuilder(
            builder: (context, setDialogState) {
              sub ??= DatabaseHelper.instance.downloadAdvancedDatabase().listen(
                (p) {
                  setDialogState(() => progress = p);
                },
                onDone: () {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                onError: (err) {
                  if (ctx.mounted) {
                    if (ctx.mounted) Navigator.pop(ctx, false);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text('Download failed: $err')),
                    );
                  }
                },
              );

              return AlertDialog(
                backgroundColor: const Color(0xFF1E293B),
                title: const Text('Downloading Scholar Lexicon', style: TextStyle(color: Colors.white)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(currentAccent),
                    ),
                    const SizedBox(height: 16),
                    Text('${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              );
            },
          ),
        );

        await sub?.cancel();
        if (success != true) return;
        }
      }
    }

    setState(() {
      _isAdvanced = isAdvanced;
      _selectedWord = null;
    });
    if (_searchController.text.trim().isNotEmpty) {
      _onSearchChanged(_searchController.text);
    }
  }

  void _toggleVoiceSearch() async {
    if (_isListening) {
      await SttService.instance.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      await SttService.instance.listen(
        onResult: (words) {
          setState(() {
            _searchController.text = words;
            _isListening = false;
          });
          _onSearchChanged(words);
        },
        onDone: () {
          setState(() => _isListening = false);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryBg = _isWireframe ? const Color(0xFF000000) : const Color(0xFF0F172A);
    final cardBg = _isWireframe ? const Color(0xFF0A0A0A) : const Color(0xFF1E293B);
    final accentAmber = currentAccent;

    return Scaffold(
      backgroundColor: primaryBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "OpenLex",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: "Theme: ${_themeMode.toUpperCase()} (tap to switch)",
            icon: Icon(
              Icons.palette_outlined,
              color: currentAccent,
            ),
            onPressed: _toggleTheme,
          ),
          IconButton(
            tooltip: _isIncognito ? "Incognito Active (No History)" : "History Enabled",
            icon: Icon(
              _isIncognito ? Icons.visibility_off : Icons.history,
              color: _isIncognito ? accentAmber : Colors.white70,
            ),
            onPressed: () {
              setState(() => _isIncognito = !_isIncognito);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_isIncognito ? "Incognito Active: Zero Data Logged" : "Search History Enabled"),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              FutureBuilder<bool>(
                future: DatabaseHelper.instance.isAdvancedDownloaded(),
                builder: (context, snapshot) {
                  final isDownloaded = snapshot.data ?? false;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ActionChip(
                        avatar: Icon(
                          isDownloaded ? Icons.check_circle_outline : Icons.cloud_download_outlined,
                          size: 16,
                          color: _isWireframe
                              ? Colors.white
                              : (isDownloaded ? currentAccent : currentAccent),
                        ),
                        label: Text(
                          isDownloaded ? "Expanded Lexicon Active" : "Expand Lexicon (+700k)",
                          style: TextStyle(
                            fontSize: 12,
                            color: _isWireframe ? Colors.white : Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        backgroundColor: _isWireframe ? Colors.transparent : cardBg,
                        side: BorderSide(
                          color: _isWireframe ? const Color(0xFF4B5563) : Colors.transparent,
                          width: _isWireframe ? 1.2 : 0.0,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        onPressed: () => _setMode(true),
                      ),
                    ),
                  );
                },
              ),
              TextField(
                focusNode: _searchFocusNode,
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) async {
              final query = value.trim().toLowerCase();
              if (query.isEmpty) return;
              FocusScope.of(context).unfocus();
              List<Map<String, dynamic>> candidates = _suggestions;
              if (candidates.isEmpty) {
                candidates = await DatabaseHelper.instance.searchPrefix(
                  query,
                  
                );
              }
              if (candidates.isNotEmpty) {
                final match = candidates.firstWhere(
                  (item) => (item['word'] as String).toLowerCase() == query,
                  orElse: () => candidates.first,
                );
                _selectWord(match['id'], isAdvanced: match['isAdvanced'] ?? false);
              }
            },
                decoration: InputDecoration(
                  hintText: "Search words, definitions...",
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic_off : Icons.mic,
                      color: _isListening ? Colors.redAccent : accentAmber,
                    ),
                    onPressed: _toggleVoiceSearch,
                  ),
                  filled: true,
                  fillColor: cardBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _isWireframe ? const Color(0xFF4B5563) : Colors.transparent,
                      width: _isWireframe ? 1.5 : 0.0,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _isWireframe ? const Color(0xFF4B5563) : Colors.transparent,
                      width: _isWireframe ? 1.5 : 0.0,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: currentAccent,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _suggestions.isNotEmpty
                    ? ListView.builder(
                        itemCount: _suggestions.length,
                        itemBuilder: (context, index) {
                          final item = _suggestions[index];
                          final isSelected = index == _selectedIndex;
                          return Card(
                            color: isSelected ? const Color(0xFF334155) : cardBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected ? accentAmber : (_isWireframe ? const Color(0xFF334155) : Colors.transparent),
                                width: 1.5,
                              ),
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(
                                item['word'],
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              subtitle: item['ipa'] != null
                                  ? Text(item['ipa'], style: TextStyle(color: accentAmber))
                                  : null,
                              onTap: () => _selectWord(item['id']),
                            ),
                          );
                        },
                      )
                    : _selectedWord != null
                        ? _buildWordDetailCard(_selectedWord!, accentAmber, cardBg)
                        : Center(
                            child: Text(
                              _isAdvanced ? "Scholar mode: literary & advanced lexicons." : "Offline, fast & zero tracking.",
                              style: const TextStyle(color: Colors.white38),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWordDetailCard(WordEntry entry, Color accent, Color cardBg) {
    return Card(
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _isWireframe ? const Color(0xFF4B5563) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.word,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      if (entry.ipa != null)
                        Text(
                          entry.ipa!,
                          style: TextStyle(fontSize: 16, color: accent, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  iconSize: 36,
                  icon: Icon(Icons.volume_up_rounded, color: accent),
                  onPressed: () => TtsService.instance.speak(entry.word),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 28),
            ...entry.senses.map((sense) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _isWireframe ? Colors.transparent : Colors.white12,
                        borderRadius: BorderRadius.circular(_isWireframe ? 20 : 6),
                        border: Border.all(
                          color: _isWireframe ? const Color(0xFF6B7280) : Colors.transparent,
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        sense.partOfSpeech.toUpperCase(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      sense.definition,
                      style: const TextStyle(fontSize: 16, color: Colors.white, height: 1.3),
                    ),
                    if (sense.example != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        "“${sense.example}”",
                        style: const TextStyle(fontSize: 14, color: Colors.white60, fontStyle: FontStyle.italic),
                      ),
                    ]
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
