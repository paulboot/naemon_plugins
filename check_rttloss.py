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
from jinja2 import Environment, PackageLoader
import locale
from typing import List, Dict, Any

locale.setlocale(locale.LC_ALL, 'nl_NL.UTF-8')

# Graphite
G_HOST = 'localhost'
G_PORT = 2003
G_PREFIX = 'ping'

# Globals
FPING = '/usr/bin/fping'
TEMPLATE_PATH = 'templates/'
HTML_PATH = '/var/www/html/actief/logisp.html'

_log = logging.getLogger('nagiosplugin')


def dict_def_status() -> Dict[str, Any]:
    status = {
        'host1.bocuse.nl': {'ip': "10.20.11.1",
                            'mac': "00-11-d8-ca-2b-a3",
                            'responses': [0.01, 0.32, "-", 10.1, "-"]
                            },
        'host2.bocuse.nl': {'ip': "10.20.11.2",
                            'mac': "00-14-d8-ca-2b-ff",
                            'responses': [0.01, 0.32, "-", 10.1, "-"]
                            },
    }
    temp = 'host3.bocuse.nl'
    status[temp] = {'ip': "1.1.1.1", 'responses': [0.05, 0.55, "-", 20.1, "-"]}

    print("Status definition")
    print(status)
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


class RttLoss(nagiosplugin.Resource):
    """Domain model: icmp echo Round trip time (RTT) and Loss."""

    def __init__(self, limit_rtt_time: float, limit_loss_perc: float, hosts: List[str], file: str):
        self.limit_rtt_time = limit_rtt_time
        self.limit_loss_perc = limit_loss_perc
        self.targets = hosts
        self.targetsfile = file
        self.packetcount = 8
        self.packetsize = 64
        self.problemtargets = []
        self.status = {}
        self.metadata = {}

    def do_rtt_loss_tests(self) -> (int, int, set):
        """Return a list of RTT and LOSS per target."""
        if not self.targets and self.targetsfile:
            with open(self.targetsfile) as targetsfile:
                self.targets = [line.strip() for line in targetsfile]

        cmd = [FPING, '-q', '-d', '-A', '-b', str(self.packetsize), '-C', str(self.packetcount)] + self.targets
        _log.info(f'querying fping with "{cmd}" command')

        hostshighrtt = 0
        hostshighloss = 0
        problemtargets = []

        self.metadata['startTimePing'] = datetime.datetime.now().strftime("%H:%M op %e %B %Y")
        _log.info(f'Stored start time: {self.metadata["startTimePing"]} in metadata dict as startTimePing')

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            _log.info(f'Found result: "{result}"')
            output = result.stderr
            _log.info(f'Found output: "{output}"')

            for line in output.splitlines():
                line = line.strip()
                _log.info(f'Found line: "{line}"')

                m = re.match(r'([^ ]*)\s+\(([^ ]*)\)\s+: (.+$)', line)
                if m:
                    target = m.group(1)
                    targetip = m.group(2)
                    _log.info(f'Found result per host for target: {target}')

                    self.status[target] = {'ip': targetip, 'limit_rtt_time': self.limit_rtt_time, 'errorlevel': 0, 'responses': []}
                    lostpackets = 0
                    results = []
                    rawresults = m.group(3).split(' ')
                    for result in rawresults:
                        if result == '-':
                            lostpackets += 1
                            self.status[target]['errorlevel'] += 1
                            self.status[target]['responses'].append(result)
                        else:
                            results.append(float(result))
                            self.status[target]['responses'].append(float(result))
                            if float(result) >= self.limit_rtt_time:
                                self.status[target]['errorlevel'] += 1

                    if results:
                        _log.info(f'Found results: "{results}"')
                        self.status[target]['min'] = min(results)
                        _log.info(f'Found min: "{self.status[target]["min"]:.2f}"')
                        self.status[target]['avg'] = average(results)
                        _log.info(f'Found avg: "{self.status[target]["avg"]:.2f}"')
                        self.status[target]['max'] = max(results)
                        _log.info(f'Found max: "{self.status[target]["max"]:.2f}"')
                        self.status[target]['median'] = median(results)
                        _log.info(f'Found median: "{self.status[target]["median"]:.2f}"')

                        if self.status[target]['median'] >= self.limit_rtt_time:
                            hostshighrtt += 1
                            problemtargets.append(target)

                    loss = (lostpackets / self.packetcount) * 100
                    _log.info(f'Found loss: "{loss:.2f}"')
                    if loss >= self.limit_loss_perc:
                        hostshighloss += 1
                        problemtargets.append(target)
            _log.info(f'Found status: "{self.status}"')

        except subprocess.CalledProcessError as e:
            raise nagiosplugin.CheckError(f'command failed: {e}')

        _log.info(f'Found number of hosts with high rtt: {hostshighrtt}')
        _log.info(f'Found number of hosts with high loss: {hostshighloss}')

        self.generate_html()

        return hostshighrtt, hostshighloss, set(problemtargets)

    def probe(self):
        """Create check metric for number of hosts who fail rtt and loss."""
        self.rtt_hosts, self.loss_hosts, self.problem_targets = self.do_rtt_loss_tests()
        return [nagiosplugin.Metric('rtt', self.rtt_hosts),
                nagiosplugin.Metric('loss', self.loss_hosts)]

    def generate_html(self):
        """Generate HTML using the self.status dictionary."""
        _log.info('Start generating HTML in generate_html')
        env = Environment(loader=PackageLoader('check_rttloss', TEMPLATE_PATH))
        template = env.get_template('fping-index.html')
        _log.info('Write HTML to file')
        with open(HTML_PATH, 'w') as file:
            file.write(template.render({'status': self.status, 'metadata': self.metadata}))
        _log.info('Done generating HTML in generate_html')


class RttLossSummary(nagiosplugin.Summary):
    """Create status line and long output."""

    def ok(self, results):
        return f'{results["rtt"]}, {results["loss"]}'

    def problem(self, results):
        return f'{results["rtt"]}, {results["loss"]}'

    def verbose(self, results):
        super().verbose(results)
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
    argp.add_argument('-l', '--limit-loss-perc', type=float, default=1,
                      help='limit loss in percentage')
    argp.add_argument('-v', '--verbose', action='count', default=0,
                      help='increase output verbosity (use up to 3 times)')
    argp.add_argument('-t', '--timeout', type=int, default=60,
                      help='abort execution after TIMEOUT seconds')
    argp.add_argument('-H', '--hosts', nargs='+',
                      help='one or more target hosts')
    argp.add_argument('-f', '--file',
                      help='a file with target hosts')
    args = argp.parse_args()
    check = nagiosplugin.Check(
        RttLoss(args.limit_rtt_time, args.limit_loss_perc, args.hosts, args.file),
        nagiosplugin.ScalarContext('rtt', args.warning_rtt_hosts, args.critical_rtt_hosts,
                                   fmt_metric='{value} hosts rtt failure'),
        nagiosplugin.ScalarContext('loss', args.warning_loss_hosts, args.critical_loss_hosts,
                                   fmt_metric='{value} hosts loss failure'),
        RttLossSummary())
    check.main(args.verbose, args.timeout)


if __name__ == '__main__':
    main()

