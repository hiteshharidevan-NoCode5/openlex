import os

target = os.path.expanduser('~/openlex/lib/core/database/database_helper.dart')

content = """import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Directory, File;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:archive/archive.dart';
import '../../models/word_entry.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _simpleDb;
  static Database? _advancedDb;
  static DatabaseFactory? _dbFactory;

  static const String _scholarDbUrl =
      'https://github.com/hiteshharidevan-NoCode5/openlex/releases/download/v1.0.0-scholar/lexicon_700k.db.gz';

  DatabaseHelper._init();

  DatabaseFactory get factory {
    if (kIsWeb) {
      _dbFactory ??= databaseFactoryFfiWeb;
      return _dbFactory!;
    }
    return databaseFactory;
  }

  Future<String> _getDbFilePath(String fileName) async {
    if (kIsWeb) {
      return fileName;
    }
    final dbDir = await getDatabasesPath();
    final path = join(dbDir, fileName);
    await Directory(dirname(path)).create(recursive: true);
    return path;
  }

  Future<bool> isAdvancedDownloaded() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('scholar_db_downloaded') ?? false;
    }
    final path = await _getDbFilePath('scholar_dict.db');
    final file = File(path);
    return await file.exists() && (await file.length()) > 1024 * 1024;
  }

  Stream<double> downloadAdvancedDatabase() async* {
    final client = http.Client();
    try {
      final uri = kIsWeb
          ? Uri.base.resolve('assets/db/lexicon_700k.db.gz')
          : Uri.parse(_scholarDbUrl);

      final request = http.Request('GET', uri);
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Failed to download database: HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? (70 * 1024 * 1024);
      int bytesReceived = 0;
      final chunks = <List<int>>[];

      await for (final chunk in response.stream) {
        chunks.add(chunk);
        bytesReceived += chunk.length;
        if (contentLength > 0) {
          yield (bytesReceived / contentLength) * 0.85;
        }
      }

      final compressedBytes = Uint8List(bytesReceived);
      int offset = 0;
      for (final chunk in chunks) {
        compressedBytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      yield 0.90;
      debugPrint('[OpenLex DB] Decompressing 70MB gzip stream...');
      final decompressedList = GZipDecoder().decodeBytes(compressedBytes);
      final totalBytes = Uint8List.fromList(decompressedList);
      debugPrint('[OpenLex DB] Uncompressed SQLite size: ${totalBytes.length} bytes');

      yield 0.95;
      final path = await _getDbFilePath('scholar_dict.db');

      if (kIsWeb) {
        debugPrint('[OpenLex DB] Writing to Web IndexedDB...');
        await factory.writeDatabaseBytes(path, totalBytes);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('scholar_db_downloaded', true);
        _advancedDb = null;
      } else {
        final file = File(path);
        await file.writeAsBytes(totalBytes, flush: true);
      }

      yield 1.0;
      debugPrint('[OpenLex DB] Scholar database ready.');
    } finally {
      client.close();
    }
  }

  Future<void> deleteAdvancedDatabase() async {
    if (_advancedDb != null && _advancedDb!.isOpen) {
      await _advancedDb!.close();
      _advancedDb = null;
    }
    final path = await _getDbFilePath('scholar_dict.db');
    if (kIsWeb) {
      await factory.deleteDatabase(path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('scholar_db_downloaded', false);
    } else {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<Database> _getDatabase({required bool isAdvanced}) async {
    if (isAdvanced) {
      if (_advancedDb != null && _advancedDb!.isOpen) return _advancedDb!;
      final path = await _getDbFilePath('scholar_dict.db');
      if (!await isAdvancedDownloaded()) {
        throw StateError('Scholar database not downloaded.');
      }
      _advancedDb = await factory.openDatabase(path);
      return _advancedDb!;
    } else {
      if (_simpleDb != null && _simpleDb!.isOpen) return _simpleDb!;
      _simpleDb = await _initSimpleDB();
      return _simpleDb!;
    }
  }

  Future<Database> _initSimpleDB() async {
    final path = await _getDbFilePath('simple_dict.db');

    final exists = await factory.databaseExists(path);
    if (!exists) {
      debugPrint('[OpenLex DB] Loading assets/db/simple_dict.db...');
      ByteData data = await rootBundle.load('assets/db/simple_dict.db');
      Uint8List bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      if (kIsWeb) {
        await factory.writeDatabaseBytes(path, bytes);
      } else {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      debugPrint('[OpenLex DB] simple_dict.db initialized successfully.');
    }

    return await factory.openDatabase(path);
  }

  Future<List<Map<String, dynamic>>> searchPrefix(
    String query, {
    int limit = 15,
    bool isAdvanced = false,
  }) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    try {
      final db = await _getDatabase(isAdvanced: isAdvanced);
      final results = await db.rawQuery('''
        SELECT id, word, ipa 
        FROM words 
        WHERE word_lower LIKE ? 
        ORDER BY LENGTH(word) ASC, word ASC 
        LIMIT ?
      ''', ['$cleanQuery%', limit]);
      return results;
    } catch (e, stack) {
      debugPrint('[OpenLex ERROR] Failed search in ${isAdvanced ? "Scholar" : "Core"}: $e');
      debugPrint(stack.toString());
      return [];
    }
  }

  Future<WordEntry?> getWordDetails(int wordId, {bool isAdvanced = false}) async {
    final db = await _getDatabase(isAdvanced: isAdvanced);
    final wordRows = await db.query(
      'words',
      where: 'id = ?',
      whereArgs: [wordId],
      limit: 1,
    );

    if (wordRows.isEmpty) return null;

    final defRows = await db.query(
      'definitions',
      where: 'word_id = ?',
      whereArgs: [wordId],
    );

    List<SenseItem> senses = defRows.map((row) {
      return SenseItem(
        partOfSpeech: row['part_of_speech'] as String,
        definition: row['definition'] as String,
        example: row['example'] as String?,
      );
    }).toList();

    return WordEntry(
      id: wordRows.first['id'] as int,
      word: wordRows.first['word'] as String,
      ipa: wordRows.first['ipa'] as String?,
      senses: senses,
    );
  }
}
"""

with open(target, 'w') as f:
    f.write(content)
print("SUCCESS: database_helper.dart has been written cleanly.")
