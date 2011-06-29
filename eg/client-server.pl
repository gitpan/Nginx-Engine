#!/usr/bin/perl

use strict;
use warnings;

use Nginx::Engine;

ngxe_init '', 1000;

ngxe_server '*', 55555, sub {

    ngxe_writer $_[0], 0, 5000, '', sub {
        return if $_[1];
 
        ngxe_close $_[0]; 
    };
                      # 1 means start now
    ngxe_reader $_[0], 1, 5000, sub {
        return if $_[1]; 
        return if $_[2] !~ /\n/; # waiting for the end of line

        $_[3] = "bar\n"; # write buffer
        $_[2] = ''; # read buffer
    };

};

ngxe_client '*', "127.0.0.1", 55555, 5000, sub {
    return if $_[1];

    my $data = "foo\n";

    ngxe_reader $_[0], 0, 5000, sub {
        return if $_[1];
        return if $_[2] !~ /\n/; # waiting for the end of line

        print "received $_[2]\n";

        ngxe_close $_[0];
    };

    ngxe_writer $_[0], 1, 5000, $data, sub {
        return if $_[1];
        print "sent $data\n";
    };
};


ngxe_loop;


