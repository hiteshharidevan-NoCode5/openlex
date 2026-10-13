import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/word_entry.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  
  static Database? _simpleDb;
  static Database? _advancedDb;

  DatabaseHelper._init();

  Future<Database> _getDatabase({required bool isAdvanced}) async {
    if (isAdvanced) {
      _advancedDb ??= await _initDB('advanced_dict.db');
      return _advancedDb!;
    } else {
      _simpleDb ??= await _initDB('simple_dict.db');
      return _simpleDb!;
    }
  }

  Future<Database> _initDB(String fileName) async {
    final dbDir = await getDatabasesPath();
    final path = join(dbDir, fileName);

    await Directory(dirname(path)).create(recursive: true);

    if (!await File(path).exists() || (await File(path).length()) == 0) {
      debugPrint('[OpenLex DB] Copying asset assets/db/$fileName to $path...');
      ByteData data = await rootBundle.load('assets/db/$fileName');
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
      debugPrint('[OpenLex DB] Copied ${bytes.length} bytes for $fileName.');
    } else {
      debugPrint('[OpenLex DB] $fileName already exists at $path (${await File(path).length()} bytes).');
    }

    return await openDatabase(
      path,
      readOnly: true,
    );
  }

  Future<List<Map<String, dynamic>>> searchPrefix(
    String query, {
    int limit = 15,
    bool isAdvanced = false,
  }) async {
    final db = await _getDatabase(isAdvanced: isAdvanced);
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final results = await db.rawQuery('''
      SELECT id, word, ipa 
      FROM words 
      WHERE word_lower LIKE ? 
      ORDER BY LENGTH(word) ASC, word ASC 
      LIMIT ?
    ''', ['$cleanQuery%', limit]);

    debugPrint('[OpenLex Search] mode=${isAdvanced ? "ADVANCED" : "SIMPLE"}, query="$cleanQuery", count=${results.length}');
    return results;
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
