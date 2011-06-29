#!/usr/bin/perl

use strict;
use warnings;

use Nginx::Engine;

ngxe_init "", 256;

# Printing global message counter every second.
my $sent = 0;
ngxe_interval_set 1000, sub {
    print "$sent messages sent last second\n";
    $sent = 0;
};

ngxe_server '*', 55555, sub {
    my $cnt = 0;

    ngxe_writer $_[0], 0, 30000, '', sub {
        return if $_[1]; 

        $_[3] = "$cnt. ";
        $_[3] .= "\x0d\x0a";  
        
        # write buffer is not empty, writer will be rescheduled

        $cnt++; # counting messages for current connection
        $sent++; # all messages
    };

    ngxe_reader $_[0], 1, 30000, sub {
        return if $_[1]; 

        $_[3] = "hello\x0d\x0a";
    };
};

ngxe_loop;




