#!/usr/bin/perl

use strict;
use warnings;

use lib "./lib", "./blib/arch";

use Nginx::Engine;

ngxe_init("", 256),

ngxe_server('*', 55555, sub {

    ngxe_writer($_[0], 0, 1000,
        "HTTP/1.0 400 Bad Request\x0d\x0a".
        "Content-type: text/html\x0d\x0a".
        "\x0d\x0a".
        "Bad Request\x0d\x0a", 
    sub {
        if ($_[1]) {
            return;
        }

        ngxe_close($_[0]);
    });

    ngxe_reader($_[0], 1, 5000, sub {
        if ($_[1]) {
            return;
        }

        if ($_[2] =~ /\x0d?\x0a\x0d?\x0a/) {
            
            my $uri = '';
            if ($_[2] =~ /^GET\s+([^\s]+)/) {
                $uri = $1;
            }

            if ($uri eq '/') {
                $_[3] = "HTTP/1.0 200 OK\x0d\x0a".
                        "Content-type: text/html\x0d\x0a".
                        "\x0d\x0a".
                        "Ok\x0d\x0a";
            } elsif ($uri ne '') {
                $_[3] = "HTTP/1.0 404 Not Found\x0d\x0a".
                        "Content-type: text/html\x0d\x0a".
                        "\x0d\x0a".
                        "Not Found\x0d\x0a";
            }

            ngxe_reader_stop($_[0]);
            ngxe_writer_start($_[0]);
        } elsif (length($_[2]) > 2000) {
            ngxe_reader_stop($_[0]);
            ngxe_writer_start($_[0]);
        } 
    });

});

ngxe_loop;




