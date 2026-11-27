#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket::INET;
my ($url, $out) = @ARGV;
die "usage: pget.pl URL OUTFILE\n" unless $out;
for my $try (1 .. 4) {
    my $u = $url;
    for my $hop (1 .. 5) {
        my ($host, $path) = $u =~ m{^http://([^/]+)(/.*)$} or exit 4;
        my $s = IO::Socket::INET->new(
            PeerHost => $host, PeerPort => 80, Timeout => 20, Proto => 'tcp'
        ) or last;
        print $s "GET $path HTTP/1.0\r\nHost: $host\r\nUser-Agent: pget/1.0\r\n\r\n";
        my $status = 0;
        while (my $l = <$s>) {
            $status = $1 if $l =~ m{^HTTP/\S+\s+(\d+)};
            last if $l =~ /^\r?$/;
        }
        if ($status == 200) {
            open(my $fh, '>:raw', $out) or exit 5;
            my $buf;
            while (read($s, $buf, 65536)) { print $fh $buf; }
            close $fh;
            close $s;
            printf "ok %s %d\n", $out, (-s $out // 0);
            exit 0;
        }
        close $s;
        last;
    }
    sleep 2;
}
print "fail $url\n";
exit 1;
