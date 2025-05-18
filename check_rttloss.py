#!/usr/bin/env python3
# Copyright (c) gocept gmbh & co. kg
# See also LICENSE.txt

"""Nagios plugin to check RTT and LOSS for a large number of hosts using fping"""

import argparse
import logging
import nagiosplugin
import re
import os
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
HTML_BASE_PATH = '/var/www/html/actief'

# Configure logging
log = logging.getLogger('nagiosplugin')

def configure_logging(verbosity: int):
    if verbosity >= 2:
        logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
    elif verbosity == 1:
        logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    else:
        logging.basicConfig(level=logging.WARNING, format='%(asctime)s - %(levelname)s - %(message)s')

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
        return 0.0
    diffs = [abs(lst[i] - lst[i - 1]) for i in range(1, len(lst))]
    return sum(diffs) / len(diffs)


class RttLoss(nagiosplugin.Resource):
    """Domain model: icmp echo Round trip time (RTT) and Loss."""

    def __init__(self, limit_rtt_time: float, limit_loss_perc: float, hosts: List[str], file: str, sort_by: str, title: str):
        self.limit_rtt_time = limit_rtt_time
        self.limit_loss_perc = limit_loss_perc
        self.targets = hosts
        self.targetsfile = file
        self.packetcount = 10
        self.packetsize = 1250
        self.problemtargets = []
        self.status = {}
        self.title = title
        self.metadata = {}
        self.sort_by = sort_by

    def do_rtt_loss_tests(self) -> (int, int, set):
        """Return a list of RTT and LOSS per target."""
        if not self.targets and self.targetsfile:
            with open(self.targetsfile) as targetsfile:
                self.targets = [line.strip() for line in targetsfile]

        cmd = [FPING, '-q', '-R', '-d', '-A', '-M', '-b', str(self.packetsize), '-C', str(self.packetcount)] + self.targets
        log.info(f'Starting fping with "{cmd}" command')

        hostshighrtt = 0
        hostshighloss = 0
        problemtargets = []

        self.metadata['startTimePing'] = datetime.datetime.now().strftime("%H:%M op %e %B %Y")
        log.info(f'Stored start time: {self.metadata["startTimePing"]} in metadata dict as startTimePing')

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            output = result.stderr
            log.debug(f'Found output: "{output}"')

            if result.returncode != 0:
                log.info(f'Fping command returned non-zero exit status {result.returncode}')
        except subprocess.TimeoutExpired:
            log.error('Fping command timed out')
            raise nagiosplugin.CheckError('Fping command timed out')
        except subprocess.CalledProcessError as e:
            log.error(f'Fping command failed: {e}')
            raise nagiosplugin.CheckError(f'Fping command failed: {e}')

        for line in output.splitlines():
            line = line.strip()
            log.info(f'Found line: "{line}"')

            m = re.match(r'([^ ]*)\s+\(([^ ]*)\)\s+: (.+$)', line)
            if m:
                targetname = m.group(1)
                targetip = ipaddress.ip_address(m.group(2))
                log.info(f'Found result per host for target: {targetname}')

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
                    log.info(f'Found results: "{results}"')
                    self.status[(targetname, targetip)]['min'] = min(results)
                    log.info(f'Found min: "{self.status[(targetname, targetip)]["min"]:.2f}"')
                    self.status[(targetname, targetip)]['avg'] = average(results)
                    log.info(f'Found avg: "{self.status[(targetname, targetip)]["avg"]:.2f}"')
                    self.status[(targetname, targetip)]['max'] = max(results)
                    log.info(f'Found max: "{self.status[(targetname, targetip)]["max"]:.2f}"')
                    # Calculate and log median
                    self.status[(targetname, targetip)]['median'] = median(results)
                    log.info(f'Found median: "{self.status[(targetname, targetip)]["median"]:.2f}"')
                    # Calculate and log jitter
                    self.status[(targetname, targetip)]['jitter'] = jitter(results)
                    log.info(f'Found jitter: "{self.status[(targetname, targetip)]["jitter"]:.2f}"')

                    if self.status[(targetname, targetip)]['median'] >= self.limit_rtt_time:
                        hostshighrtt += 1
                        problemtargets.append(targetname)

                loss = (lostpackets / self.packetcount) * 100
                log.info(f'Found loss: "{loss:.2f}"')
                if loss >= self.limit_loss_perc:
                    hostshighloss += 1
                    problemtargets.append(targetname)
        log.info(f'Found status: "{self.status}"')

        log.info(f'Found number of hosts with high rtt: {hostshighrtt}')
        log.info(f'Found number of hosts with high loss: {hostshighloss}')

        # self.generate_html()

        return hostshighrtt, hostshighloss, set(problemtargets)

    def probe(self):
        """Create check metric for number of hosts who fail rtt and loss."""
        self.rtt_hosts, self.loss_hosts, self.problem_targets = self.do_rtt_loss_tests()
        log.info(f'Probe results - RTT: {self.rtt_hosts}, Loss: {self.loss_hosts}, Problem Targets: {self.problem_targets}')

        self.generate_html()

        return [nagiosplugin.Metric('rtt', self.rtt_hosts),
                nagiosplugin.Metric('loss', self.loss_hosts)]

    def generate_html(self):
        """Generate HTML using the self.status dictionary."""
        log.info('Start generating HTML in generate_html')

        env = Environment(loader=PackageLoader('check_rttloss', TEMPLATE_PATH),
                        autoescape=select_autoescape(['html', 'xml']))
        template = env.get_template('fping-index.html')

        # Sort the status dictionary
        sorted_status = {}
        if self.sort_by == 'targetname':
            sorted_keys = sorted(self.status.keys(), key=lambda item: item[0])
        elif self.sort_by == 'targetip':
            sorted_keys = sorted(self.status.keys(), key=lambda item: item[1])
        for key in sorted_keys:
            sorted_status[key] = self.status[key]

        # Determine result status
        status_folder = 'OK' if self.rtt_hosts == 0 and self.loss_hosts == 0 else 'FAILURE'

        # Get base filename from -f argument or use "manual"
        if self.targetsfile:
            basefile = os.path.splitext(os.path.basename(self.targetsfile))[0]
        else:
            basefile = 'manual'

        # Build timestamp and date
        now = datetime.datetime.now()
        date_str = now.strftime('%Y-%m-%d')
        timestamp_str = now.strftime('%Y-%m-%d_%H-%M')

        # Construct full folder path and file path
        folder_path = os.path.join(HTML_BASE_PATH, status_folder, basefile, date_str)
        os.makedirs(folder_path, exist_ok=True)

        filename = f'{basefile}-{timestamp_str}.html'
        filepath = os.path.join(folder_path, filename)
        #static_base = os.path.relpath(HTML_BASE_PATH, start=os.path.dirname(filepath))
        #static_base = static_base.replace(os.sep, '/')

        # Write HTML file
        log.info(f'Write HTML to file: {filepath}')
        with open(filepath, 'w') as file:
            file.write(template.render({
                'status': sorted_status,
                'metadata': self.metadata,
                'STATIC_BASE': '/actief',
                'now': datetime.datetime.now,
                'title': self.title
            }))

        log.info('Done generating HTML in generate_html')

        # Create/update symbolic link
        symlink_dir = os.path.join(HTML_BASE_PATH, 'LATEST')
        os.makedirs(symlink_dir, exist_ok=True)
        symlink_name = f'{basefile}-latest.html'
        symlink_path = os.path.join(symlink_dir, symlink_name)

        try:
            if os.path.islink(symlink_path) or os.path.exists(symlink_path):
                os.remove(symlink_path)
            os.symlink(filepath, symlink_path)
            log.info(f'Created symlink: {symlink_path} → {filepath}')
        except OSError as e:
            log.warning(f'Could not create symlink {symlink_path}: {e}')

class RttLossSummary(nagiosplugin.Summary):
    """Create status line and long output."""

    def ok(self, results):
        log.info(f'OK results: {results}')
        return f'{results["rtt"]}, {results["loss"]}'

    def problem(self, results):
        log.info(f'Problem results: {results}')
        return f'{results["rtt"]}, {results["loss"]}'

    def verbose(self, results):
        super().verbose(results)
        log.info(f'Verbose results: {results}')
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
    argp.add_argument('--title', default='fpinguru Report',
                      help='Title for the HTML report')
    argp.add_argument('-H', '--hosts', nargs='+',
                      help='one or more target hosts')
    argp.add_argument('-f', '--file',
                      help='a file with target hosts')
    argp.add_argument('-s', '--sort-by', choices=['targetname', 'targetip'], default='targetip',
                      help='sort the output by targetname or targetip')
    args = argp.parse_args()

    # Configure logging based on verbosity
    configure_logging(args.verbose)

    check = nagiosplugin.Check(
        RttLoss(args.limit_rtt_time, args.limit_loss_perc, args.hosts, args.file, args.sort_by, args.title),
        nagiosplugin.ScalarContext('rtt', args.warning_rtt_hosts, args.critical_rtt_hosts,
                                   fmt_metric='#{value} hosts rtt failure'),
        nagiosplugin.ScalarContext('loss', args.warning_loss_hosts, args.critical_loss_hosts,
                                   fmt_metric='#{value} hosts loss failure'),
        RttLossSummary())
    check.main(args.verbose, args.timeout)

if __name__ == '__main__':
    main()
