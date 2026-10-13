import sqlite3
import os
import nltk
from nltk.corpus import wordnet as wn

POS_MAP = {
    'n': 'noun',
    'v': 'verb',
    'a': 'adjective',
    's': 'adjective',
    'r': 'adverb'
}

def create_schema(cursor):
    cursor.execute("DROP TABLE IF EXISTS definitions;")
    cursor.execute("DROP TABLE IF EXISTS words;")
    cursor.execute("""
        CREATE TABLE words (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word TEXT NOT NULL,
            word_lower TEXT NOT NULL,
            ipa TEXT
        );
    """)
    cursor.execute("""
        CREATE TABLE definitions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word_id INTEGER NOT NULL,
            part_of_speech TEXT NOT NULL,
            definition TEXT NOT NULL,
            example TEXT,
            FOREIGN KEY (word_id) REFERENCES words(id)
        );
    """)
    cursor.execute("CREATE INDEX idx_words_lower ON words(word_lower);")
    cursor.execute("CREATE INDEX idx_defs_word_id ON definitions(word_id);")

def build_lexicons():
    print("Collecting WordNet lexical items...")
    raw_lemmas = wn.all_lemma_names()
    
    # Filter out multi-word underscore entries for simple, keep clean single/hyphenated tokens
    word_map = {}
    
    for lemma in raw_lemmas:
        clean = lemma.strip()
        if not clean or clean.startswith('_'):
            continue
        display_word = clean.replace('_', ' ')
        key = clean.lower().replace('_', ' ')
        
        synsets = wn.synsets(lemma)
        if not synsets:
            continue
            
        # Tally sense count for sorting/tiering
        sense_count = len(synsets)
        
        entries = []
        for s in synsets:
            pos = POS_MAP.get(s.pos(), 'noun')
            defn = s.definition()
            examples = s.examples()
            ex = examples[0] if examples else None
            entries.append((pos, defn, ex))
            
        word_map[key] = {
            'word': display_word,
            'word_lower': key,
            'senses': sense_count,
            'entries': entries
        }

    print(f"Total distinct headwords extracted: {len(word_map)}")

    # Simple dict: Single words, prioritized by polysemy/commonality (top ~35k)
    # Advanced dict: Complete lexicon
    simple_candidates = [
        item for item in word_map.values()
        if ' ' not in item['word'] and '-' not in item['word'] and item['word'].isalpha()
    ]
    simple_candidates.sort(key=lambda x: x['senses'], reverse=True)
    
    # Take top 35,000 for simple, plus core words
    simple_words = set(w['word_lower'] for w in simple_candidates[:35000])
    
    # Explicitly ensure target words are present in simple
    for guaranteed in ['grandeur', 'granular', 'lexicon', 'serendipity', 'resilience', 'pragmatic']:
        if guaranteed in word_map:
            simple_words.add(guaranteed)

    # 1. Build Simple DB
    simple_db_path = os.path.expanduser("~/openlex/assets/db/simple_dict.db")
    print(f"Populating {simple_db_path}...")
    conn_simple = sqlite3.connect(simple_db_path)
    cur_simple = conn_simple.cursor()
    create_schema(cur_simple)

    cur_simple.execute("BEGIN TRANSACTION;")
    word_id = 1
    for k, item in word_map.items():
        if k in simple_words:
            cur_simple.execute(
                "INSERT INTO words (id, word, word_lower, ipa) VALUES (?, ?, ?, ?)",
                (word_id, item['word'], item['word_lower'], None)
            )
            for pos, defn, ex in item['entries']:
                cur_simple.execute(
                    "INSERT INTO definitions (word_id, part_of_speech, definition, example) VALUES (?, ?, ?, ?)",
                    (word_id, pos, defn, ex)
                )
            word_id += 1
    conn_simple.commit()
    cur_simple.execute("VACUUM;")
    conn_simple.close()

    # 2. Build Advanced DB
    adv_db_path = os.path.expanduser("~/openlex/assets/db/advanced_dict.db")
    print(f"Populating {adv_db_path}...")
    conn_adv = sqlite3.connect(adv_db_path)
    cur_adv = conn_adv.cursor()
    create_schema(cur_adv)

    cur_adv.execute("BEGIN TRANSACTION;")
    word_id = 1
    for k, item in word_map.items():
        cur_adv.execute(
            "INSERT INTO words (id, word, word_lower, ipa) VALUES (?, ?, ?, ?)",
            (word_id, item['word'], item['word_lower'], None)
        )
        for pos, defn, ex in item['entries']:
            cur_adv.execute(
                "INSERT INTO definitions (word_id, part_of_speech, definition, example) VALUES (?, ?, ?, ?)",
                (word_id, pos, defn, ex)
            )
        word_id += 1
    conn_adv.commit()
    cur_adv.execute("VACUUM;")
    conn_adv.close()

    print("Database population complete.")

if __name__ == '__main__':
    build_lexicons()
