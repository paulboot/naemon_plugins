#!/usr/bin/python
# Copyright (c) Paul Boot (paulboot(at)gmail.com)
# See also LICENSE.txt

"""XXX Nagios plugin to check XXX"""

# ToDo:
# -Per afdeling-id ophalen

# VOORBEELD:
# met twee contexts en in verbose mode meerdere regels output!
# second context is not a scalar but a text output scalar, just used for reporting.

# Dependancies
# sudo apt-get install python-pip
# sudo pip --proxy http://proxy.gg.nl:8080/ install nagiosplugin --upgrade
# sudo locale-gen nl_NL.UTF-8

# Testing the URL takes about 30 seconds!
# wget --no-proxy -O output.txt
#   http://gg.nl/PlanService/getfeed.aspx?id=uitloop&link=schedule&showzerodelay=n

import requests
import argparse
import pickle
import logging
import nagiosplugin
import re
from lxml import etree

import locale
locale.setlocale(locale.LC_ALL, 'nl_NL.UTF-8')


# Globals
ignoredepartments = ['Apotheek', 'Dialyse', 'Cardio Research',
                     'Cardiologie Planning', 'Laboratorium', 'Logopedie']

NO_PROXY = {
    'http': '',
    'https': ''
}

URL_uitloop = '/PlanService/getfeed.aspx?id=uitloop&link=schedule&showzerodelay=n'
pickle_path = '/usr/local/naemon/var/'
pickle_file = '_check_uitloop_all.pkl'

# Parsed data format
# <item>
# <pubDate>Tue, 03 May 2018 09:21:51 GMT</pubDate>
# <title>Uitloop Cardiologie - dr. v.d. Plas: 25 minuten.</title>
# <link>http://localhost/iDoc.Web.Services/PlanService/GetFeed.aspx?ID=uitloop</link>
# <description>Uitloop Cardiologie - dr. v.d. Plas: 25 minuten.</description>
# <logisp:type>uitloop</logisp:type>
# <logisp:department>A00104</logisp:department>
# <logisp:departmentname>Cardiologie</logisp:departmentname>
# <logisp:routeinfo></logisp:routeinfo>
# <logisp:shortrouteinfo></logisp:shortrouteinfo>
# <logisp:resource>dr. v.d. Plas</logisp:resource>
# <logisp:uitloopminuten>25</logisp:uitloopminuten>
# </item>

# Parse title line: 'Uitloop Cardiologie - dr. v.d. Plas: 30 minuten'

_log = logging.getLogger('nagiosplugin')


class UITLOOP(nagiosplugin.Resource):
    """Resource creation"""

    def __init__(self, uitloopminuten, hostname):

        self.uitloopminuten = int(uitloopminuten)
        self.hostname = str(hostname)

    def probe(self):

        # uitloopdict = {
        #    'Cardiologie' : { 'Jansen' : { 'uitloopminuten' : 20 },
        #                      'Pietersen' : { 'uitloopminuten' : 60 } },
        #    'XXXXlogie' : { 'XJansen' : { 'uitloopminuten' : 20 },
        #                      'XPietersen' : { 'uitloopminuten' : 60 } }
        #    }
        # pprint.pprint(uitloopdict)

        uitloopdict = {}
        aantaluitloopafdelingen = 0

        URL = 'http://' + self.hostname + URL_uitloop
        _log.debug('###DEBUG fetching URL: %s', URL)

        r = requests.get(URL, proxies=NO_PROXY)
        _log.debug('###DEBUG URL_uitloop status code: %r', r.status_code)
        # print r.content

        parser = etree.XMLParser(ns_clean=True, recover=True, encoding='utf-8')
        xml = etree.fromstring(r.content, parser)

        for element in xml.iter():
            if element.tag == 'title' and element.text != 'Uitloop':
                _log.debug('Found <title> tag with contents: %s', element.text)
                searchObj = re.match(r'Uitloop\s(.*?)\s-\s(.*?):\s(\d*)\sminuten.', element.text)
                if searchObj:
                    departmentname = searchObj.group(1)
                    resource = searchObj.group(2)
                    uitloopminuten = int(searchObj.group(3))

                    if departmentname not in ignoredepartments:
                        if uitloopminuten > self.uitloopminuten:
                            if not uitloopdict.has_key(departmentname):
                                uitloopdict[departmentname] = {}
                            if not uitloopdict[departmentname].has_key(resource):
                                uitloopdict[departmentname][resource] = {}
                            uitloopdict[departmentname][resource]['uitloopminuten'] = uitloopminuten
                            aantaluitloopafdelingen += 1
                else:
                    _log.info('Uitloop string NOT found in <title> line: %s', element.text)
        # pprint.pprint(uitloopdict))
        output = open(pickle_path + self.hostname + pickle_file, 'wb', -1)
        pickle.dump(uitloopdict, output)
        output.close()

        return [nagiosplugin.Metric('aantaluitloopafdelingen', aantaluitloopafdelingen, min=0),
                nagiosplugin.Metric('tekst', uitloopdict)]


class UitloopSummary(nagiosplugin.Summary):
    """Status regel output functies."""

    def problem(self, results):
        problemText = ''
        for afdeling in sorted(results['tekst'].metric.value):
            problemText += "%s - " % afdeling
            for naam in results['tekst'].metric.value[afdeling]:
                problemText += "%s: %d min. " % (naam,
                                                 results['tekst'].metric.value[afdeling][naam]['uitloopminuten'])
        return problemText.encode('ascii', 'ignore')

    def verbose(self, results):
        verboseText = '\nEr is uitloop geconstateerd op de volgende afdelingen:\n'
        for afdeling in sorted(results['tekst'].metric.value):
            verboseText += "\n%s - " % afdeling
            for naam in results['tekst'].metric.value[afdeling]:
                verboseText += "%s: %d minuten. " % (
                    naam, results['tekst'].metric.value[afdeling][naam]['uitloopminuten'])
        return verboseText.encode('ascii', 'ignore')


@nagiosplugin.guarded
def main():
    argp = argparse.ArgumentParser()
    argp.add_argument('-w', '--warning', metavar='RANGE', default=1,
                      help='warning niveau maximaal aantal afdelingen met uitloop')
    argp.add_argument('-c', '--critical', metavar='RANGE', default=3,
                      help='critical niveau maximaal aantal afdelingen met uitloop')
    argp.add_argument('-u', '--uitloopminuten', metavar='RANGE', default=45,
                      help='maximale uitloop in minuten')
    argp.add_argument('-v', '--verbose', action='count', default=0,
                      help='increase output verbosity (use up to 3 times)')
    argp.add_argument('-t', '--timeout', type=int, default=60,
                      help='abort execution after TIMEOUT seconds')
    argp.add_argument('-H', '--hostname',
                      help='host name argument for webservices URL')
    argp.add_argument('-p', '--port', type=int, default=80,
                      help='port number (default: 80)')
    args = argp.parse_args()
    check = nagiosplugin.Check(
        UITLOOP(args.uitloopminuten, args.hostname),
        nagiosplugin.ScalarContext('aantaluitloopafdelingen', args.warning,
                                   args.critical, fmt_metric='{value} maximale uitloop in minuten'),
        nagiosplugin.Context('tekst'),
        UitloopSummary())
    check.main(verbose=args.verbose, timeout=args.timeout)


if __name__ == '__main__':
    main()
