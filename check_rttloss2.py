#!/usr/bin/env python3
# Copyright (c) gocept gmbh & co. kg
# See also LICENSE.txt

"""Nagios plugin to check RTT and LOSS for a large number of hosts using fping"""

import argparse
import logging
import nagiosplugin
import re
import datetime
import subprocess
from jinja2 import Environment, PackageLoader, select_autoescape
import locale
from typing import List, Dict, Any
import ipaddress
from pprint import pprint

locale.setlocale(locale.LC_ALL, 'nl_NL.UTF-8')

# Graphite
G_HOST = 'localhost'
G_PORT = 2003
G_PREFIX = 'ping'

# Globals
FPING = '/usr/bin/fping'
TEMPLATE_PATH = 'templates/'
HTML_PATH = '/var/www/html/actief/logisp.html'


def setup_logging(level):
    # Configure the logging
    logging.basicConfig(level=level,
                        format='%(asctime)s - %(levelname)s - %(message)s',
                        datefmt='%Y-%m-%d %H:%M:%S')


def dict_def_status() -> Dict[str, Any]:
    status = {
        ('host1.bocuse.nl', ipaddress.IPv4Address("10.20.11.1")): {
            'ip': ipaddress.IPv4Address("10.20.11.1"),
            'mac': "00-11-d8-ca-2b-a3",
            'responses': [0.01, 0.32, "-", 10.1, "-"]
        },
        ('host2.bocuse.nl', ipaddress.IPv4Address("10.20.11.2")): {
            'ip': ipaddress.IPv4Address("10.20.11.2"),
            'mac': "00-14-d8-ca-2b-ff",
            'responses': [0.01, 0.32, "-", 10.1, "-"]
        },
    }
    temp = ('host3.bocuse.nl', ipaddress.IPv4Address("1.1.1.1"))
    status[temp] = {
        'ip': ipaddress.IPv4Address("1.1.1.1"),
        'responses': [0.05, 0.55, "-", 20.1, "-"]
    }

    print("Status definition")
    pprint(status)
    print()
    return status

def dict_def_metadata() -> Dict[str, str]:
    metadata = {'startTimePing': datetime.datetime.now().strftime("%H:%M op %B %d, %Y")}
    return metadata

def to_float(lst: List[str]) -> List[Any]:
    return [float(x) if x.replace('.', '', 1).isdigit() else x for x in lst]

def average(lst: List[float]) -> float:
    return sum(lst) / len(lst)

def median(lst: List[float]) -> float:
    sorted_list = sorted(lst)
    mid = len(sorted_list) // 2
    if len(sorted_list) % 2 == 0:
        return (sorted_list[mid - 1] + sorted_list[mid]) / 2.0
    return sorted_list[mid]

def jitter(lst: List[float]) -> float:
    if len(lst) < 2:
        return 0.0  # Jitter is 0 if there are less than 2 round-trip times

    # Calculate differences between consecutive round-trip times
    differences = [abs(lst[i] - lst[i - 1]) for i in range(1, len(lst))]

    # Calculate the average of these differences
    jitter = sum(differences) / len(differences)

    return jitter


class RttLoss(nagiosplugin.Resource):
    """Domain model: icmp echo Round trip time (RTT) and Loss."""

    def __init__(self, limit_rtt_time: float, limit_loss_perc: float, hosts: List[str], file: str, sort_by: str):
        self.limit_rtt_time = limit_rtt_time
        self.limit_loss_perc = limit_loss_perc
        self.targets = hosts
        self.targetsfile = file
        self.packetcount = 10
        self.packetsize = 512
        self.problemtargets = []
        self.status = {}
        self.metadata = {}
        self.sort_by = sort_by

    def do_rtt_loss_tests(self) -> (int, int, set):
        """Return a list of RTT and LOSS per target."""
        if not self.targets and self.targetsfile:
            with open(self.targetsfile) as targetsfile:
                self.targets = [line.strip() for line in targetsfile]

        cmd = [FPING, '-q', '-d', '-A', '-R', '-b', str(self.packetsize), '-C', str(self.packetcount)] + self.targets
        logging.info(f'Starting fping with "{cmd}" command')

        hostshighrtt = 0
        hostshighloss = 0
        problemtargets = []

        self.metadata['startTimePing'] = datetime.datetime.now().strftime("%H:%M op %e %B %Y")
        logging.info(f'Stored start time: {self.metadata["startTimePing"]} in metadata dict as startTimePing')

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            output = result.stderr
            logging.debug(f'Found output: "{output}"')

            if result.returncode != 0:
                logging.info(f'Fping command returned non-zero exit status {result.returncode}')
        except subprocess.TimeoutExpired:
            logging.error('Fping command timed out')
            raise nagiosplugin.CheckError('Fping command timed out')
        except subprocess.CalledProcessError as e:
            logging.error(f'Fping command failed: {e}')
            raise nagiosplugin.CheckError(f'Fping command failed: {e}')

        for line in output.splitlines():
            line = line.strip()
            logging.info(f'Found line: "{line}"')

            m = re.match(r'([^ ]*)\s+\(([^ ]*)\)\s+: (.+$)', line)
            if m:
                targetname = m.group(1)
                targetip = ipaddress.ip_address(m.group(2))
                logging.info(f'Found result per host for target: {targetname}')

                self.status[(targetname, targetip)] = {
                    'ip': targetip,
                    'limit_rtt_time': self.limit_rtt_time,
                    'errorlevel': 0,
                    'responses': []
                }
                lostpackets = 0
                results = []
                rawresults = m.group(3).split(' ')
                for result in rawresults:
                    if result == '-':
                        lostpackets += 1
                        self.status[(targetname, targetip)]['errorlevel'] += 1
                        self.status[(targetname, targetip)]['responses'].append(result)
                    else:
                        results.append(float(result))
                        self.status[(targetname, targetip)]['responses'].append(float(result))
                        if float(result) >= self.limit_rtt_time:
                            self.status[(targetname, targetip)]['errorlevel'] += 1

                if results:
                    logging.info(f'Found results: "{results}"')
                    self.status[(targetname, targetip)]['min'] = min(results)
                    logging.info(f'Found min: "{self.status[(targetname, targetip)]["min"]:.2f}"')
                    self.status[(targetname, targetip)]['avg'] = average(results)
                    logging.info(f'Found avg: "{self.status[(targetname, targetip)]["avg"]:.2f}"')
                    self.status[(targetname, targetip)]['max'] = max(results)
                    logging.info(f'Found max: "{self.status[(targetname, targetip)]["max"]:.2f}"')
                    self.status[(targetname, targetip)]['median'] = median(results)
                    logging.info(f'Found median: "{self.status[(targetname, targetip)]["median"]:.2f}"')
                    self.status[(targetname, targetip)]['jitter'] = jitter(results)
                    logging.info(f'Found jitter: "{self.status[(targetname, targetip)]["jitter"]:.2f}"')

                    if self.status[(targetname, targetip)]['median'] >= self.limit_rtt_time:
                        hostshighrtt += 1
                        problemtargets.append(targetname)

                loss = (lostpackets / self.packetcount) * 100
                logging.info(f'Found loss: "{loss:.2f}"')
                if loss >= self.limit_loss_perc:
                    hostshighloss += 1
                    problemtargets.append(targetname)
        logging.debug(f'Found status: "{self.status}"')

        logging.info(f'Found number of hosts with high rtt: {hostshighrtt}')
        logging.info(f'Found number of hosts with high loss: {hostshighloss}')

        self.generate_html()

        return hostshighrtt, hostshighloss, set(problemtargets)

    def probe(self):
        """Create check metric for number of hosts who fail rtt and loss."""
        self.rtt_hosts, self.loss_hosts, self.problem_targets = self.do_rtt_loss_tests()
        logging.info(f'Probe results - RTT: {self.rtt_hosts}, Loss: {self.loss_hosts}, Effected targets: {self.problem_targets}')
        return [nagiosplugin.Metric('rtt', self.rtt_hosts),
                nagiosplugin.Metric('loss', self.loss_hosts)]

    def generate_html(self):
        """Generate HTML using the self.status dictionary."""
        logging.info('Start generating HTML in generate_html')
        env = Environment(loader=PackageLoader('check_rttloss', TEMPLATE_PATH), autoescape=select_autoescape(['html', 'xml']))
        template = env.get_template('fping-index.html')

        # Sort the status dictionary by the specified attribute
        sorted_status = {}
        if self.sort_by == 'targetname':
            sorted_keys = sorted(self.status.keys(), key=lambda item: item[0])
        elif self.sort_by == 'targetip':
            sorted_keys = sorted(self.status.keys(), key=lambda item: item[1])
        for key in sorted_keys:
            sorted_status[key] = self.status[key]

        logging.info('Write HTML to file')
        with open(HTML_PATH, 'w') as file:
            file.write(template.render({'status': sorted_status, 'metadata': self.metadata}))
        logging.info('Done generating HTML in generate_html')

class RttLossSummary(nagiosplugin.Summary):
    """Create status line and long output."""

    def ok(self, results):
        logging.info(f'OK results: {results}')
        return f'{results["rtt"]}, {results["loss"]}'

    def problem(self, results):
        logging.info(f'Problem results: {results}')
        return f'{results["rtt"]}, {results["loss"]}'

    def verbose(self, results):
        super().verbose(results)
        logging.info(f'Verbose results: {results}')
        if 'rtt' in results:
            return f'problem hosts: {", ".join(results["rtt"].resource.problem_targets)}'

@nagiosplugin.guarded
def main():
    argp = argparse.ArgumentParser()
    argp.add_argument('-w', '--warning-rtt-hosts', metavar='RANGE',
                      help='warning if # of hosts with rtt is outside RANGE')
    argp.add_argument('-c', '--critical-rtt-hosts', metavar='RANGE',
                      help='critical if # of hosts with rtt is outside RANGE')
    argp.add_argument('-W', '--warning-loss-hosts', metavar='RANGE',
                      help='warning if # of hosts with loss is outside RANGE')
    argp.add_argument('-C', '--critical-loss-hosts', metavar='RANGE',
                      help='critical if # of hosts with loss is outside RANGE')
    argp.add_argument('-r', '--limit-rtt-time', type=float, default=100,
                      help='limit median rtt in ms')
    argp.add_argument('-L', '--limit-loss-perc', type=float, default=1,
                      help='limit loss in percentage')
    argp.add_argument('-v', '--verbose', action='count', default=0,
                      help='increase output verbosity (use up to 3 times)')
    argp.add_argument('-l', '--log', dest='log_level', action='store',
                      choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'],
                      default='ERROR',
                      help='set the logging level (default: WARNING).')
    argp.add_argument('-t', '--timeout', type=int, default=60,
                      help='abort execution after TIMEOUT seconds')
    argp.add_argument('-H', '--hosts', nargs='+',
                      help='one or more target hosts')
    argp.add_argument('-f', '--file',
                      help='a file with target hosts')
    argp.add_argument('-s', '--sort-by', choices=['targetname', 'targetip'], default='targetip',
                      help='sort the output by targetname or targetip')
    args = argp.parse_args()

    # Configure logging based on verbosity
    log_level = args.log_level.upper()
    setup_logging(log_level)

    check = nagiosplugin.Check(
        RttLoss(args.limit_rtt_time, args.limit_loss_perc, args.hosts, args.file, args.sort_by),
        nagiosplugin.ScalarContext('rtt', args.warning_rtt_hosts, args.critical_rtt_hosts,
                                   fmt_metric='#{value} hosts rtt failure'),
        nagiosplugin.ScalarContext('loss', args.warning_loss_hosts, args.critical_loss_hosts,
                                   fmt_metric='#{value} hosts loss failure'),
        RttLossSummary())
    check.main(args.verbose, args.timeout)

if __name__ == '__main__':
    main()
