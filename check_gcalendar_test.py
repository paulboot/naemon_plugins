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
        self.assertAlmostEqual(c._eventgethours('Uren: NP10 P4 Km: K MKBoZ K'), 14)
        self.assertAlmostEqual(c._eventgethours('Uren: NP10 P14 Km: K MKBoZ K'), 24)

    def test_invalidhours(self):
        self.assertRaises(ValueError, c._eventgethours, 'Urn: NP4 P4 Km: K MKBoZ K')
        self.assertRaises(ValueError, c._eventgethours, 'Uren: NP4P4 Km: K MKBoZ K')
