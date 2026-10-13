import sqlite3
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "../../assets/db/simple_dict.db")

def build_schema(cur):
    cur.execute("PRAGMA page_size = 4096;")
    cur.execute("PRAGMA journal_mode = OFF;")
    cur.execute("PRAGMA synchronous = 0;")
    cur.execute("PRAGMA cache_size = -8000;")

    cur.execute("""
    CREATE TABLE IF NOT EXISTS words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL,
        word_lower TEXT NOT NULL,
        ipa TEXT
    );
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_words_lower ON words(word_lower);")

    cur.execute("""
    CREATE TABLE IF NOT EXISTS definitions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id INTEGER NOT NULL,
        part_of_speech TEXT NOT NULL,
        definition TEXT NOT NULL,
        example TEXT,
        FOREIGN KEY (word_id) REFERENCES words(id)
    );
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_defs_word_id ON definitions(word_id);")

def insert_batch(conn, entries):
    cur = conn.cursor()
    for item in entries:
        word = item['word'].strip()
        ipa = item.get('ipa', '')
        senses = item.get('senses', [])
        
        if not word or not senses:
            continue

        cur.execute("INSERT INTO words (word, word_lower, ipa) VALUES (?, ?, ?);",
                    (word, word.lower(), ipa))
        word_id = cur.lastrowid

        for sense in senses:
            pos = sense.get('pos', 'general')
            defn = sense.get('definition', '').strip()
            example = sense.get('example', None)
            if defn:
                cur.execute("""
                INSERT INTO definitions (word_id, part_of_speech, definition, example)
                VALUES (?, ?, ?, ?);
                """, (word_id, pos, defn, example))
    conn.commit()

def process_data_source(conn):
    starter_lexicon = [
        {"word": "lexicon", "ipa": "/ˈlɛksɪkən/", "senses": [{"pos": "noun", "definition": "The vocabulary of a person, language, or branch of knowledge.", "example": "The size of the English lexicon is vast."}]},
        {"word": "ephemeral", "ipa": "/ɪˈfɛmərəl/", "senses": [{"pos": "adjective", "definition": "Lasting for a very short time; transitory.", "example": "Fashions are ephemeral, but style endures."}]},
        {"word": "perspicacious", "ipa": "/ˌpɜːrspɪˈkeɪʃəs/", "senses": [{"pos": "adjective", "definition": "Having a ready insight into and understanding of things.", "example": "Her perspicacious analysis solved the issue."}]},
        {"word": "serendipity", "ipa": "/ˌsɛrənˈdɪpɪti/", "senses": [{"pos": "noun", "definition": "The occurrence of events by chance in a happy or beneficial way.", "example": "Finding that rare volume was pure serendipity."}]},
        {"word": "resilient", "ipa": "/rɪˈzɪliənt/", "senses": [{"pos": "adjective", "definition": "Able to withstand or recover quickly from difficult conditions.", "example": "A resilient community recovers swiftly from hardship."}]},
        {"word": "ubiquitous", "ipa": "/juːˈbɪkwɪtəs/", "senses": [{"pos": "adjective", "definition": "Present, appearing, or found everywhere.", "example": "Smartphones have become ubiquitous in daily life."}]},
        {"word": "lucid", "ipa": "/ˈluːsɪd/", "senses": [{"pos": "adjective", "definition": "Expressed clearly; easy to understand.", "example": "He gave a lucid summary of the core principles."}]},
        {"word": "eloquent", "ipa": "/ˈɛləkwənt/", "senses": [{"pos": "adjective", "definition": "Fluent or persuasive in speaking or writing.", "example": "An eloquent speaker can move an entire audience."}]},
        {"word": "pragmatic", "ipa": "/præɡˈmætɪk/", "senses": [{"pos": "adjective", "definition": "Dealing with things sensibly and realistically based on practical considerations.", "example": "We need a pragmatic approach to solving the bottleneck."}]},
        {"word": "meticulous", "ipa": "/mɪˈtɪkjələs/", "senses": [{"pos": "adjective", "definition": "Showing great attention to detail; very careful and precise.", "example": "He was meticulous in maintaining the archives."}]}
    ]

    print("Inserting lexical records into SQLite...")
    insert_batch(conn, starter_lexicon)

def main():
    abs_db_dir = os.path.dirname(os.path.abspath(DB_PATH))
    os.makedirs(abs_db_dir, exist_ok=True)
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    build_schema(cur)
    process_data_source(conn)

    cur.execute("VACUUM;")
    cur.execute("PRAGMA optimize;")
    conn.commit()
    conn.close()
    print(f"✓ Database successfully compiled at: {os.path.abspath(DB_PATH)}")

if __name__ == "__main__":
    main()

