#!/usr/bin/perl

use bytes;
use strict;
use warnings;

use Nginx::Engine;
use Socket;

ngxe_init("", 256);

# Connecting to the cpan.perl.org and 
# showing the list of recent uploads.

my $host    = "cpan.perl.org";
my $addr    = inet_ntoa(inet_aton($host));
my $request = "GET / HTTP/1.0\x0d\x0a".
              "Host: $host\x0d\x0a".
              "\x0d\x0a";

ngxe_client('*', $addr, 80, 5000, sub {

    if ($_[1]) {
        warn "Cannot connect\n";
        return;
    }

    ngxe_reader($_[0], 0, 5000, sub {

        # $_[1] - error indicator
        if ($_[1]) {

            # we are waiting for connection to be closed and
            # only then parsing the response

            if ($_[2]) {
                while ($_[2] =~ m!(http://search.cpan.org/~[^"]+)!gs) {
                    print "$1\n";
                }
            }

            exit;
            return;
        }

    });

    ngxe_writer($_[0], NGXE_START, 5000, $request, sub {
        if ($_[1]) {
            return;
        }
    });

});
         
ngxe_loop;




