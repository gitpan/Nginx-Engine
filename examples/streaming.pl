#!/usr/bin/perl

use bytes;
use strict;
use warnings;

use Nginx::Engine;

ngxe_init("", 256);

my $sent = 0;

ngxe_interval_set(1000, sub {
    print "$sent messages sent last second\n";
    $sent = 0;
});

ngxe_server('*', 55555, sub {
    ngxe_reader($_[0], NGXE_START, 5000, sub {
        return if $_[1];

        $_[3] = "hello\x0d\x0a";
    });

    ngxe_writer($_[0], 0, 1000, '', sub {
        return if $_[1];

        $_[3] .= "$_[4]. ";
        $_[3] .= "\x0d\x0a";

        $_[4]++; # using stored argument to count messages for current
                 # connection

        $sent++;
    }, 1);
});

ngxe_loop;




