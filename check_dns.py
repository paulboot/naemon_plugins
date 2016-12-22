#!/usr/bin/python

#check commands
#check_command  check_dns!www.example.nl!cname=www1.example.nl
#check_command  check_dns!www1.example.nl!a=192.168.1.1

#define command {
#  command_name                   check_dns
#  command_line                   $USER1$/check_dns.py $ARG1$ $ARG2$
#}

import optparse
import os
import dns
import dns.exception
import dns.rdatatype
import dns.resolver
import sys

def dnscheck(domain, rdtype, expected=None, timeout=None):
    """
    Queries the rdtype records of the domain its authoritive nameservers and
    checks whether the received answers are all equal to the expected answer.
    """
    if timeout is None: timeout = 10.0
    answers = resolve_authoritive(domain, rdtype, timeout)
    if not answers:
        print "%s %s no answer" % (domain, dns.rdatatype.to_text(rdtype))
        return False
    elif not equal_answers(answers):
        print "%s %s different answers, expected %s" % (domain,
                dns.rdatatype.to_text(rdtype), list_to_text(expected))
        for nameserver, answer in answers.items():
            rrs = get_rrs(answer, rdtype)
            print " nameserver %s: %s %s" % (nameserver,
                    dns.rdatatype.to_text(rdtype), list_to_text(rrs))
        return False
    answer = answers.values()[0]
    rrs = get_rrs(answer, rdtype)
    if set(rrs) == set(expected):
        print "%s %s %s" % (domain, dns.rdatatype.to_text(rdtype),
                list_to_text(rrs))
        return True
    else:
        print "%s %s %s, expected %s" % (domain,
                dns.rdatatype.to_text(rdtype), list_to_text(rrs),
                list_to_text(expected))
        return False


def equal_answers(answers):
    rrsets = answers.values()
    return all(rrset == rrsets[0] for rrset in rrsets[1:]) if rrsets else True

def get_rrs(answer, rdtype):
    rrsets = [rrset for rrset in answer if rrset.rdtype == rdtype]
    if rrsets:
        assert len(rrsets) <= 1, "Multiple %s record sets: %s" \
                % (dns.rdatatype.to_text(rdtype), answer)
        return [rr.to_text().replace(' ', ':').rstrip('.') for rr in rrsets[0]]
    else:
        return []

def list_to_text(l):
    return ','.join(l) if l else 'EMPTY'

def resolve_authoritive(domain, rdtype, timeout):
    nameservers = find_nameservers(domain)
    nsanswers = {}
    for nameserver in nameservers:
        answers = dns.resolver.query(nameserver, dns.rdatatype.A)
        nsaddresses = [answer.address for answer in answers]
        for nsaddress in nsaddresses:
            request = dns.message.make_query(domain, rdtype)
            try:
                response = dns.query.udp(request, nsaddress, timeout)
            except dns.resolver.NXDOMAIN:
                continue
            if response is None:
                continue
            nsanswers[nsaddress] = response.answer
    return nsanswers

def find_nameservers(domain):
    while domain:
        try:
            answers = dns.resolver.query(domain, dns.rdatatype.NS)
        except dns.exception.DNSException:
            pass
        else:
            return [answer.target for answer in answers]
        dotpos = domain.find('.')
        if dotpos > 0:
            domain = domain[dotpos+1:]
        else:
            raise dns.resolver.NoAnswer("Error finding nameserver for %s"
                    % domain)

def error(argv, msg):
    basename = os.path.basename(argv[0])
    print >>sys.stderr, "%s: error: %s" % (basename, msg)
    sys.exit(2)

class ExampleHelpFormatter(optparse.IndentedHelpFormatter):
    def format_epilog(self, epilog):
        if epilog:
            return "\n" + epilog
        else:
            return ""

def main(argv):
    # Set-up command line parser
    usage = "%prog [OPTIONS] DOMAIN TYPE=EXPECTED[,EXPECTED...]"
    epilog = """
Examples:
  %prog www.example.com a=192.168.1.1
  %prog fr.example.com cname=www.example.com
  %prog example.com mx=10:192.168.1.2,20:192.168.1.3
    """.strip() + '\n'
    parser = optparse.OptionParser(formatter=ExampleHelpFormatter())
    parser.set_usage(usage)
    parser.epilog = epilog.replace("%prog", parser.get_prog_name())
    parser.add_option("-t", "--timeout", dest="timeout",
            type="float", default=10.0,
            help="set the DNS query timeout to TIMEOUT seconds",
            metavar="TIMEOUT")

    # Parse command line
    (options, args) = parser.parse_args()
    if len(args) != 2:
        parser.error("incorrect number of arguments")
    domain = args[0]
    try:
        typearg, exparg = args[1].split('=')
    except ValueError:
        parser.error("incorrect TYPE=EXPECTED argument: %s" % args[1])
    try:
        rdtype = dns.rdatatype.from_text(typearg)
    except dns.rdatatype.UnknownRdatatype:
        parser.error("unknown TYPE: %s" % typearg)
    if exparg == 'EMPTY':
        exparg = ''
    expected = exparg.split(',') if exparg else ()

    # Execute DNS check
    try:
        return 0 if dnscheck(domain, rdtype, expected, options.timeout) else 1
    except dns.resolver.NoAnswer, e:
        error(argv, e.message)
    except dns.exception.Timeout, e:
        error(argv, "timeout waiting for nameserver")

if __name__ == "__main__":
    sys.exit(main(sys.argv))
    
