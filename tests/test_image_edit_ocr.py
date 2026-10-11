"""Exercise production image/OCR update SQL without requiring an iOS runtime."""
from pathlib import Path
import re
import sqlite3
import unittest


SOURCE = (Path(__file__).resolve().parents[1] / "Core/Manager/KayokoHistoryStore.m").read_text()


def statement_in(method):
    body = SOURCE.split(method, 1)[1].split("\n- (", 1)[0]
    match = re.search(r'executeStatement:((?:@?"[^"\n]*"\s*)+)\s*bindings:', body)
    if not match:
        raise AssertionError(f"No update statement found in {method}")
    return "".join(re.findall(r'"([^"\n]*)"', match.group(1)))


EDIT_SQL = statement_in("- (NSDictionary<NSString *, id> *)updateImageForItemDictionary:")
OCR_SQL = statement_in("- (BOOL)setOCRText:")


class ImageEditOCRTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.execute("""CREATE TABLE history_items (
            history_key TEXT, content TEXT, image_name TEXT, image_width INTEGER,
            image_height INTEGER, image_byte_count INTEGER, updated_at REAL,
            ocr_text TEXT NOT NULL DEFAULT '', note TEXT, tag_uuid TEXT,
            PRIMARY KEY (history_key, content))""")
        for key in ("history", "favorites"):
            self.db.execute("INSERT INTO history_items VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                            (key, "original.png", "original.png", 1200, 2400, 100, 1,
                             "private number", "keep note", "keep tag"))

    def tearDown(self):
        self.db.close()

    def edit(self, old, new, width=600, height=800):
        return self.db.execute(EDIT_SQL, (new, new, width, height, 200, 2,
                                         "history", old, old)).rowcount

    def recognize(self, image, text, key="history"):
        return self.db.execute(OCR_SQL, (text, key, image, image)).rowcount

    def test_redaction_invalidates_old_ocr_and_preserves_metadata(self):
        self.assertEqual(self.edit("original.png", "edited.png"), 1)
        row = self.db.execute("SELECT ocr_text,note,tag_uuid,image_width,image_height "
                              "FROM history_items WHERE history_key='history'").fetchone()
        self.assertEqual(row, ("", "keep note", "keep tag", 600, 800))
        self.assertEqual(self.recognize("original.png", "stale private number"), 0)
        self.assertEqual(self.recognize("edited.png", "visible text"), 1)
        self.assertEqual(self.db.execute("SELECT ocr_text FROM history_items WHERE history_key='history'")
                         .fetchone()[0], "visible text")

    def test_restore_invalidates_edited_ocr_and_allows_original_recognition(self):
        self.edit("original.png", "edited.png")
        self.recognize("edited.png", "annotation text")
        self.assertEqual(self.edit("edited.png", "original.png", 1200, 2400), 1)
        self.assertEqual(self.db.execute("SELECT ocr_text FROM history_items WHERE history_key='history'")
                         .fetchone()[0], "")
        self.assertEqual(self.recognize("edited.png", "late annotation text"), 0)
        self.assertEqual(self.recognize("original.png", "original text"), 1)

    def test_favorites_are_isolated_from_history_edits(self):
        self.edit("original.png", "edited.png")
        self.assertEqual(self.db.execute("SELECT content,ocr_text,note,tag_uuid FROM history_items "
                                         "WHERE history_key='favorites'").fetchone(),
                         ("original.png", "private number", "keep note", "keep tag"))
        self.assertEqual(self.recognize("original.png", "updated favorite OCR", "favorites"), 1)

    def test_image_identity_guard_rejects_changed_image_with_same_content(self):
        self.db.execute("UPDATE history_items SET image_name='replacement.png' WHERE history_key='history'")
        self.assertEqual(self.recognize("original.png", "stale"), 0)
        self.assertEqual(self.edit("original.png", "wrong.png"), 0)


if __name__ == "__main__":
    unittest.main()
