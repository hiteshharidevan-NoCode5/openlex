class SenseItem {
  final String partOfSpeech;
  final String definition;
  final String? example;

  SenseItem({
    required this.partOfSpeech,
    required this.definition,
    this.example,
  });
}

class WordEntry {
  final int id;
  final String word;
  final String? ipa;
  final List<SenseItem> senses;

  WordEntry({
    required this.id,
    required this.word,
    this.ipa,
    required this.senses,
  });
}
