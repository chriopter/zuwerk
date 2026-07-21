"""Tests for the initial Zuwerk application."""

import unittest
from app import PAGE


class PageTests(unittest.TestCase):
    def test_page_introduces_zuwerk(self) -> None:
        page = PAGE.decode("utf-8")
        self.assertIn("<h1>Zuwerk</h1>", page)
        self.assertIn("Projects for humans and agents", page)


if __name__ == "__main__":
    unittest.main()
