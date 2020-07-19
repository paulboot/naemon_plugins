#!/usr/bin/python3

import unittest
from check_gcalendar import Calendar
from apiclient.discovery import build
from google.oauth2 import service_account

SCOPES = ['https://www.googleapis.com/auth/calendar.readonly']
try:
    gcredentials = service_account.Credentials.from_service_account_file(
        '/etc/naemon/secrets/gsecrets.json', scopes=SCOPES)
except FileNotFoundError:
    raise FileNotFoundError('File with gsecrets not found') from None
except Exception:
    raise

gcalendar = build('calendar', 'v3', credentials=gcredentials)
c = Calendar(gcalendar)


class TestCalendarCheck(unittest.TestCase):
    def test_validhours(self):
        self.assertAlmostEqual(c._eventgethours('Uren: NP8 Km: K MKBoZ K'), 8)
        self.assertAlmostEqual(c._eventgethours('Uren: NP4 P4 Km: K MKBoZ K'), 8)
        self.assertAlmostEqual(c._eventgethours('Uren: NP10 P4 Km: K MKBoZ K'), 14)
        self.assertAlmostEqual(c._eventgethours('Uren: NP10 P14 Km: K MKBoZ K'), 24)

    def test_invalidhours(self):
        self.assertRaises(ValueError, c._eventgethours, 'Urn: NP4 P4 Km: K MKBoZ K')
        self.assertRaises(ValueError, c._eventgethours, 'Uren: NP4P4 Km: K MKBoZ K')

    def test_eventsum(self):
        self.assertEqual(c._eventsum(), 'Vrij:')

    def tearDown(self):
        print('Bye Test')


if __name__ == '__main__':
    unittest.main()
