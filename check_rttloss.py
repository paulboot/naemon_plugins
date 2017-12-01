#!/usr/bin/python
# Copyright (c) gocept gmbh & co. kg
# See also LICENSE.txt

"""Nagios plugin to check RTT en LOSS for large number of hosts using fping"""

# Dependancies
# sudo apt-get install python-pip
# sudo pip --proxy http://proxydlf.rdgg.nl:8080/ install nagiosplugin
# sudo locale-gen nl_NL.UTF-8

import argparse
import logging
import nagiosplugin
import re
import subprocess
import datetime
from jinja2 import Environment, PackageLoader #@UnresolvedImport

import locale
locale.setlocale(locale.LC_ALL, 'nl_NL.UTF-8')
#locale.setlocale(locale.LC_ALL, ('nl_NL', 'utf8@euro'))

# Graphite
g_host = 'localhost'
g_port = 2003
g_prefix = 'ping'

# Globals
fping = '/usr/bin/fping'
templatepath = 'templates/'
htmlpath = '/var/www/html/actief/logisp.html' 

_log = logging.getLogger('nagiosplugin')

def dict_def_status():
    status = {
                'host1.bocuse.nl' : {   'ip' : "10.20.11.1",
                                        'mac' : "00-11-d8-ca-2b-a3",
                                        'responses' : [ 0.01, 0.32, "-", 10.1, "-" ]
                                    },
                'host2.bocuse.nl' : {   'ip' : "10.20.11.2",
                                        'mac' : "00-14-d8-ca-2b-ff",
                                        'responses' : [ 0.01, 0.32, "-", 10.1, "-" ]
                                    },
    }
    temp = 'host3.bocuse.nl'
    status[temp]={}
    status[temp]['ip'] = "1.1.1.1"
    status[temp]['responses']=[]
    status[temp]['responses'].append(0.05)
    status[temp]['responses'] += [0.55, "-", 20.1, "-" ]

    print "Status definition"
    print status
    print
    return status

def dict_def_metadata():
    metadata['startTimePing']=datetime.datetime.now().strftime("%H:%M op %B %d, %Y")
    return metadata

def tofloat(list):
    for x in list:
        try:
            yield float(x)
        except ValueError:
            yield x

def avg(list):
    sum = 0.0
    for x in list:
        sum += x
    return sum/(len(list))

def median(list):
    srtd = sorted(list) # returns a sorted copy
    mid = len(list)/2   # remember that integer division truncates
    if len(list) % 2 == 0:  # take the avg of middle two
        return (srtd[mid-1] + srtd[mid]) / 2.0
    else:
        return srtd[mid]

class RttLoss(nagiosplugin.Resource):
    """Domain model: icmp echo Round trip time(Rtt) and Loss.

    The `RttLoss` class is a model of system aspects relevant for this
    check.
    """

    def __init__(self, limit_rtt_time, limit_loss_perc, hosts, file):
        self.limit_rtt_time = limit_rtt_time
        self.limit_loss_perc = limit_loss_perc
        self.targets = hosts
        self.targetsfile = file
        self.packetcount = 8
        self.packetsize = 64
        self.problemtargets = []
        self.status = {}
        self.metadata = {}
    
    def do_rtt_loss_tests(self):
        """Return a list of RTT en LOSS per target.

        The Roundtrip and Loss list is determined by invoking an external command
        defined in `fping` and parsing its output. The
        command is expected to produce multiple lines.
        """
        
        #rtt = {}
        #loss = {}
        #for t in self.targets:
        #    rtt[t] = []
        #    loss[t] = {}
        
        if self.targets:
            cmd = [ fping, '-q', '-d', '-A', '-b', str(self.packetsize), '-C', str(self.packetcount) ]
        else:
            cmd = [ fping, '-q', '-d', '-A', '-b', str(self.packetsize), '-C', str(self.packetcount) ]
            if self.targetsfile:
                with open(self.targetsfile) as targetsfile:
                    self.targets = [line.strip() for line in targetsfile]
        
        _log.info('querying fping with "%s" command', cmd)
        _log.info('going to ping targets "%s"', self.targets)

        hostshighrtt = 0
        hostshighloss = 0
        problemtargets = []
                
        try:
            self.metadata['startTimePing']=datetime.datetime.now().strftime("%H:%M op %e %B %Y")
            _log.info('Stored start time: %s in metadata dict as startTimePing',  self.metadata['startTimePing'])
            ping = subprocess.Popen(cmd, bufsize=256, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.PIPE)
            _log.info('Going to write to STDIN "%s"', self.targets)
            ping.stdin.write('\n'.join(self.targets))
            for rawline in ping.communicate()[0].splitlines():
                line = rawline.rstrip()
                _log.info('Found line: "%s"', line)
                
                #ap1 : 0.65 0.73 0.73
                #rt1 : 0.31 0.30 0.31
                m = re.match('([^ ]*)\s+\(([^ ]*)\)\s+: (.+$)', line)
                if m:
                    target = m.group(1)
                    targetip = m.group(2)
                    _log.info('Found result per host for target: %s' , target)
                    
                    self.status[target] = {}
                    self.status[target]['ip'] = targetip
                    self.status[target]['limit_rtt_time'] = self.limit_rtt_time
                    self.status[target]['errorlevel'] = 0
                    self.status[target]['responses'] = []
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

                    if len(results) != 0:
                        #results = list(tofloat(results))
                        _log.info('Found results: "%s"', results)
                        self.status[target]['min'] = min(results)
                        _log.info('Found min: "%.2f"', self.status[target]['min'])
                        self.status[target]['avg'] = avg(results)
                        _log.info('Found avg: "%.2f"', self.status[target]['avg'])
                        self.status[target]['max'] = max(results)
                        _log.info('Found max: "%.2f"', self.status[target]['max'])
                        self.status[target]['median'] = median(results)
                        _log.info('Found median: "%.2f"', self.status[target]['median'])

                        if self.status[target]['median'] >= self.limit_rtt_time:
                            hostshighrtt += 1
                            problemtargets.append(target)
                    
                    loss = 0.0
                    loss = (lostpackets / self.packetcount) * 100
                    _log.info('Found loss: "%.2f"', loss)
                    if loss >= self.limit_loss_perc:
                        hostshighloss +=1
                        problemtargets.append(target)
            _log.info('Found status: "%s"', self.status)
                
        except OSError:
            raise nagiosplugin.CheckError(
                'command OSError:  ({0} failed)'.format(cmd))

        _log.info('Found number of hosts with high rrt: %d', hostshighrtt)
        _log.info('Found number of hosts with high loss: %d', hostshighloss)
        
        self.generate_html()
        
        return (hostshighrtt, hostshighloss, set(problemtargets))

    def probe(self):
        """Create check metric for number of hosts who fail rtt and loss.

        This method returns two metrics: `rtt` and 'loss'.
        """
        (self.rtt_hosts, self.loss_hosts, self.problem_targets) = self.do_rtt_loss_tests()
        return [nagiosplugin.Metric('rtt', self.rtt_hosts),
                nagiosplugin.Metric('loss', self.loss_hosts)]

    def generate_html(self):
        """
        Generate HTML using the self.status dictionary.
        
        :param hostname: status of all tests
        :rtype: string with HTML tabel
        """
        _log.info('Start generating HTML in generate_html')
        env = Environment(loader=PackageLoader('check_rttloss', templatepath))
        template = env.get_template('fping-index.html')
        _log.info('Write HTML to file')
        file = open(htmlpath, 'w')
        file.write(template.render({'status' : self.status, 'metadata' : self.metadata }))
        file.close()
        _log.info('Done generating HTML in generate_html')
        
        return 

class RttLossSummary(nagiosplugin.Summary):
    """Create status line and long output.

    For the status line, the text snippets created by the contexts work
    quite well, so leave `ok` and `problem` with their default
    implementations. For the long output (-v) we wish to display *which*
    users are actually logged in. Note how we use the `resource`
    attribute in the resuls object to grab this piece of information
    from the domain model object.
    """

    def ok(self, results):
        return str(results['rtt']) + ', ' + str(results['loss'])
        
    def problem(self, results):
        return str(results['rtt']) + ', ' + str(results['loss'])
        #return str(results['rtt'].resource.rtt_hosts) + ', ' + str(results['loss'].resource.loss_hosts)
        #return str(results[0])
        
    def verbose(self, results):
        super(RttLossSummary, self).verbose(results)
        #print results['rtt'].resource.rtt_hosts
        #print results['rtt'].resource.loss_hosts
        #print results['rtt'].resource.problem_targets
        if 'rtt' in results:
            #return 'XXXX: ' + ', '.join(results['loss'])
            return 'problem hosts: ' + ', '.join(results['rtt'].resource.problem_targets)
            
class RttLossResult(nagiosplugin.Result):
    """Evaluation outcome consisting of state and explanation.

    A Result object is typically emitted by a
    :class:`~nagiosplugin.context.Context` object and represents the
    outcome of an evaluation. It contains a
    :class:`~nagiosplugin.state.ServiceState` as well as an explanation.
    Plugin authors may subclass Result to implement specific features.
    """

    def __str__(self):
        """Textual result explanation.

        The result explanation is taken from :attr:`metric.description`
        (if a metric has been passed to the constructur), followed
        optionally by the value of :attr:`hint`. This method's output
        should consist only of a text for the reason but not for the
        result's state. The latter is rendered independently.

        :returns: result explanation or empty string
        """
        if self.metric and self.metric.description:
            desc = self.metric.description
        else:
            desc = None
        if self.hint and desc:
            return '{0} A{1}A'.format(desc, self.hint)
        elif self.hint:
            return self.hint
        elif desc:
            return desc
        else:
            return ''



@nagiosplugin.guarded
def main():
    argp = argparse.ArgumentParser()
    argp.add_argument('-w', '--warning-rtt-hosts', metavar='RANGE',
                      help='warning if # of hosts with rtt is outside RANGE'),
    argp.add_argument('-c', '--critical-rtt-hosts', metavar='RANGE',
                      help='critical if # of hosts with rtt is outside RANGE')
    argp.add_argument('-W', '--warning-loss-hosts', metavar='RANGE',
                      help='warning if # of hosts with loss is outside RANGE')
    argp.add_argument('-C', '--critical-loss-hosts', metavar='RANGE',
                      help='critical if # of hosts with loss is outside RANGE')
    argp.add_argument('-r', '--limit-rtt-time', type=float, default=10,
                      help='limit median rrt in ms')
    argp.add_argument('-l', '--limit-loss-perc', type=float, default=5,
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
