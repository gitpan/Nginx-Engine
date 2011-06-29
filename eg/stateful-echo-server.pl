#!/usr/bin/perl

use strict;
use warnings;

use Nginx::Engine;

ngxe_init "", 256;

ngxe_server '*', 55555, sub {

    # using perl's context (scope) to access
    # the state SV, which is a lot more cleaner 
    # way than using stored arguments

    my $state = 0;

    ngxe_writer $_[0], 0, 5000, '', sub {
        return if $_[1]; 
    };

    ngxe_reader $_[0], 1, 5000, sub {
        return if $_[1]; 

        # state 0
        if ($state == 0) {
            $_[3] = $_[2]; 
            $_[2] = '';

            $state = 1; # to state 1 next time
        } elsif ($state == 1) {
            $_[3] = uc($_[2]); 
            $_[2] = '';

            $state = 0; # back to 0
        }
    };
};

ngxe_loop;




