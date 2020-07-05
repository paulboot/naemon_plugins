import unittest
import nagiosplugin
import logging
import re

from check_gcalendar import Calendar

c = Calendar(None)


class TestCalendar_eventgethours(unittest.TestCase):
    def test_validhours(self):
        self.assertAlmostEqual(c._eventgethours('Uren: NP8 Km: K MKBoZ K'), 8)
        self.assertAlmostEqual(c._eventgethours('Uren: NP4 P4 Km: K MKBoZ K'), 8)

    def test_invalidhours(self):
        self.assertRaises(AttributeError, c._eventgethours, 'Urn: NP4P4 Km: K MKBoZ K')
