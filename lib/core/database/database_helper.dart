import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Directory, File, IOSink, gzip;
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
      'https://github.com/hiteshharidevan-NoCode5/openlex/releases/download/v1.0.1/lexicon_700k.db.gz';

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
    if (kIsWeb) {
      throw UnsupportedError('Scholar 700k database is only supported on native Android.');
    }
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(_scholarDbUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Failed to download database: HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? (70 * 1024 * 1024);
      int bytesReceived = 0;

      final path = await _getDbFilePath('scholar_dict.db');
      final tempFile = File('$path.tmp');
      final sink = tempFile.openWrite();

      // Measure compressed download progress while piping directly through gzip.decoder to disk
      final progressStream = response.stream.map((chunk) {
        bytesReceived += chunk.length;
        return chunk;
      });

      final decompressionFuture = progressStream
          .transform(gzip.decoder)
          .pipe(sink);

      while (bytesReceived < contentLength) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (contentLength > 0) {
          yield (bytesReceived / contentLength).clamp(0.0, 0.95);
        }
        if (bytesReceived >= contentLength) break;
      }

      await decompressionFuture;
      yield 0.98;

      if (await File(path).exists()) {
        await File(path).delete();
      }
      await tempFile.rename(path);

      final prefs = await SharedPreferences.getInstance();
      final remoteVer = await fetchRemoteScholarVersion() ?? 1;
      await prefs.setInt(_scholarVersionKey, remoteVer);
      _advancedDb = null;

      yield 1.0;
      debugPrint('[OpenLex DB] Scholar database streamed to disk successfully.');
    } finally {
      client.close();
    }
  }

  static const String _scholarVersionKey = 'scholar_db_version';

  Future<int> getLocalScholarVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_scholarVersionKey) ?? 0;
  }

  Future<int?> fetchRemoteScholarVersion() async {
    try {
      final uri = kIsWeb
          ? Uri.base.resolve('assets/db/version.json')
          : Uri.parse('https://raw.githubusercontent.com/hiteshharidevan-NoCode5/openlex/main/assets/db/version.json');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['version'] as int?;
      }
    } catch (e) {
      debugPrint('[OpenLex DB] Unable to check remote version: $e');
    }
    return null;
  }

  Future<bool> checkScholarUpdateAvailable() async {
    if (!await isAdvancedDownloaded()) return false;
    final remoteVersion = await fetchRemoteScholarVersion();
    if (remoteVersion == null) return false;
    final localVersion = await getLocalScholarVersion();
    return remoteVersion > localVersion;
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
      await prefs.remove(_scholarVersionKey);
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
    final path = await _getDbFilePath('core_advanced_v1.db');

    final exists = await factory.databaseExists(path);
    if (!exists) {
      debugPrint('[OpenLex DB] Loading assets/db/advanced_dict.db...');
      ByteData data = await rootBundle.load('assets/db/advanced_dict.db');
      Uint8List bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      if (kIsWeb) {
        await factory.writeDatabaseBytes(path, bytes);
      } else {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      debugPrint('[OpenLex DB] simple_dict.db initialized successfully.');
    }

    return await factory.openDatabase(path);
  }  Future<List<Map<String, dynamic>>> _queryWordsFromDb(
    Database db,
    String cleanQuery,
    String strippedQuery,
    int limit,
    bool isAdv,
  ) async {
    final rawResults = await db.rawQuery('''
      SELECT id, word, ipa 
      FROM words 
      WHERE word_lower LIKE ? 
      ORDER BY word_lower ASC 
      LIMIT ?
    ''', ['$cleanQuery%', limit]);

    List<Map<String, dynamic>> results = rawResults.map((r) => {
      ...r,
      'isAdvanced': isAdv,
    }).toList();

    if (results.length < limit && strippedQuery.isNotEmpty && strippedQuery != cleanQuery) {
      final secondary = await db.rawQuery('''
        SELECT id, word, ipa 
        FROM words 
        WHERE word_lower LIKE ? 
        ORDER BY word_lower ASC 
        LIMIT ?
      ''', ['$strippedQuery%', limit - results.length]);

      final seenIds = results.map((r) => r["id"]).toSet();
      for (final row in secondary) {
        if (!seenIds.contains(row["id"])) {
          results.add({
            ...row,
            'isAdvanced': isAdv,
          });
        }
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> searchPrefix(
    String query, {
    int limit = 15,
    bool? isAdvanced,
  }) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];
    final strippedQuery = cleanQuery.replaceAll(RegExp(r"['\.\-_ ]"), "");

    try {
      if (isAdvanced != null) {
        final db = await _getDatabase(isAdvanced: isAdvanced);
        return await _queryWordsFromDb(db, cleanQuery, strippedQuery, limit, isAdvanced);
      }

      final coreDb = await _getDatabase(isAdvanced: false);
      final coreResults = await _queryWordsFromDb(coreDb, cleanQuery, strippedQuery, limit, false);

      final hasScholar = await isAdvancedDownloaded();
      if (!hasScholar || coreResults.length >= limit) {
        return coreResults;
      }

      final scholarDb = await _getDatabase(isAdvanced: true);
      final scholarResults = await _queryWordsFromDb(
        scholarDb,
        cleanQuery,
        strippedQuery,
        limit,
        true,
      );

      final seenWords = coreResults.map((r) => (r["word"] as String).toLowerCase()).toSet();
      final combined = List<Map<String, dynamic>>.from(coreResults);

      for (final row in scholarResults) {
        final w = (row["word"] as String).toLowerCase();
        if (!seenWords.contains(w)) {
          seenWords.add(w);
          combined.add(row);
          if (combined.length >= limit) break;
        }
      }
      return combined;
    } catch (e, stack) {
      debugPrint('[OpenLex ERROR] Failed search: $e');
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
