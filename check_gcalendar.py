#!/usr/bin/python3

# REFERECE: https://developers.google.com/calendar/
# https://stackoverflow.com/questions/27326650/
#  how-to-access-domain-users-calendar-using-service-account-in-net
# https://stackoverflow.com/questions/27325089/
#  google-calendar-v3-api-with-oauth-2-0-service-account-return-empty-result

from datetime import datetime, timedelta
from apiclient.discovery import build
from google.oauth2 import service_account
import argparse
import nagiosplugin
import logging

_log = logging.getLogger('nagiosplugin')

# If modifying these scopes, delete the file token.json.
# SCOPES = [ 'https://www.googleapis.com/auth/calendar',
# 'https://www.googleapis.com/auth/calendar.readonly',
# 'https://www.googleapis.com/auth/calendar.events.readonly' ]
# https://www.googleapis.com/auth/calendar.events.readonly'
# SCOPES = ['https://www.googleapis.com/auth/calendar.readonly']
SCOPES = ['https://www.googleapis.com/auth/calendar.readonly']

TIMEZONE = 'Europe/Amsterdam'
EVENTSTART = '2020-06-18T08:00:00'
EVENTEND = '2020-06-18T08:30:00'
SUMMARY = 'Uren NP 8? KM MeldkmrBOZ?'
EVENT = {
    'summary': SUMMARY,
    'start': {'dateTime': EVENTSTART, 'timeZone': TIMEZONE},
    'end': {'dateTime': EVENTEND, 'timeZone': TIMEZONE},
}


class Calendar(nagiosplugin.Resource):
    """ Subclass of Resource to collecte the resource

    A Google calendar will be queried for a "Uren" entry today
    """

    def __init__(self, gcalendar):
        self.gcalendar = gcalendar

    def probe(self):
        return [nagiosplugin.Metric('calendar', self.eventlist())]

    def eventlist(self):
        # 2020-06-18T19:55:01.874999Z
        now = datetime.utcnow() - timedelta(days=1)
        now_start_rfc = now.strftime("%Y-%m-%dT08:00:00+02:00")
        now_end_rfc = now.strftime("%Y-%m-%dT08:30:00+02:00")

        events = self.gcalendar.events().list(calendarId='paulboot@gmail.com',
                                              timeMin=now_start_rfc,
                                              timeMax=now_end_rfc,
                                              maxResults=10, singleEvents=True,
                                              orderBy='startTime').execute()

        if not events:
            _log.info('No events listed.')
            return ''

        for event in events['items']:
            # _log.debug(event)
            if (event['start']['dateTime'] == now_start_rfc and
                    event['end']['dateTime'] == now_end_rfc):
                if (event['summary'].startswith("Uren ") or
                        event['summary'].startswith("Vrij")):
                    _log.info("Gevonden summary: " + event['summary'])
                    return event['summary']
        return ''


class UrenContext(nagiosplugin.Context):

    def evaluate(self, metric, resource):
        """Determines state of a given metric.

        This base implementation returns :class:`~nagiosplugin.state.Ok`
        in all cases. Plugin authors may override this method in
        subclasses to specialize behaviour.

        :param metric: associated metric that is to be evaluated
        :param resource: resource that produced the associated metric
            (may optionally be consulted)
        :returns: :class:`~.result.Result` or
            :class:`~.state.ServiceState` object
        """
        if metric.valueunit == '':
            return self.result_cls(nagiosplugin.Critical, metric=metric)
        else:
            if '?' in metric.valueunit:
                return self.result_cls(nagiosplugin.Critical, metric=metric)
            else:
                return self.result_cls(nagiosplugin.Ok, metric=metric)


@nagiosplugin.guarded
def main():
    """Shows basic usage of the Google Calendar API.

    Nagios check an Google calendar if an event is found starting 08:00 and
    ending 08:30 in now() minus 1 day that has a calendar summary
    description starting with "Uren " or "Vrij" then Ok state
    else Critical state.

    """
    argp = argparse.ArgumentParser()
    argp.add_argument('-v', '--verbose', action='count', default=0,
                      help='increase output verbosity (use up to 3 times)')
    argp.add_argument('-t', '--timeout', default=30,
                      help='abort execution after TIMEOUT seconds')
    args = argp.parse_args()

    gcredentials = service_account.Credentials.from_service_account_file(
        '/etc/naemon/secrets/gsecrets.json', scopes=SCOPES)
    gcalendar = build('calendar', 'v3', credentials=gcredentials)

    check = nagiosplugin.Check(Calendar(gcalendar), UrenContext('calendar'))
    check.main(args.verbose)


if __name__ == '__main__':
    main()
