import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from text_prep import TextError, prepare_text  # noqa: E402


class PrepareTextTest(unittest.TestCase):
    def test_keeps_allowed_tags_lowercased(self):
        self.assertEqual(prepare_text("Aww [Chuckle] that's cute. [SIGH]"), "Aww [chuckle] that's cute. [sigh]")

    def test_multiword_tag(self):
        self.assertEqual(prepare_text("[clear  throat] Okay."), "[clear throat] Okay.")

    def test_drops_unknown_tags(self):
        self.assertEqual(prepare_text("Hey [softly] you [pause]."), "Hey you.")

    def test_drops_actions_and_stage_directions(self):
        self.assertEqual(prepare_text("*hugs you* Come here (smiling). （轻声）Okay?"), "Come here. Okay?")

    def test_collapses_whitespace(self):
        self.assertEqual(prepare_text("  Mm,\n\n  I'm   here.  "), "Mm, I'm here.")

    def test_empty(self):
        for text in ["", "   ", None, 42]:
            with self.assertRaises(TextError) as ctx:
                prepare_text(text)
            self.assertEqual(ctx.exception.code, "empty_text")

    def test_too_long(self):
        with self.assertRaises(TextError) as ctx:
            prepare_text("a" * 401, max_chars=400)
        self.assertEqual(ctx.exception.code, "text_too_long")

    def test_only_tags_or_directions_is_empty(self):
        for text in ["[laugh]", "*sighs* (quietly)", "[whatever]..."]:
            with self.assertRaises(TextError) as ctx:
                prepare_text(text)
            self.assertEqual(ctx.exception.code, "empty_after_cleanup")

    def test_mixed_chinese_kept(self):
        self.assertEqual(prepare_text("Good night, 宝贝."), "Good night, 宝贝.")


if __name__ == "__main__":
    unittest.main()
