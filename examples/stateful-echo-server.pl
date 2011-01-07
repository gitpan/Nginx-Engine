#!/usr/bin/perl

use strict;
use warnings;

use Nginx::Engine;

ngxe_init("", 256);

ngxe_server('*', 55555, sub {

    ngxe_writer($_[0], 0, 1000, '', sub {
        return if $_[1]; 
    });

    ngxe_reader($_[0], NGXE_START, 5000, sub {
        return if $_[1]; 

        # state 0
        if ($_[5] == 0) {
            $_[3] .= $_[2]; 
            $_[2] = '';

            $_[5] = 1; # to state one next time
        } elsif ($_[5] == 1) {
            $_[3] .= uc($_[2]); 
            $_[2] = '';

            $_[5] = 0; # back to 0
        }
    }, 0);

});

ngxe_loop;




