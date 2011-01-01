#!/usr/bin/perl

use bytes;
use strict;
use warnings;

use Nginx::Engine;

ngxe_init("", 256);

ngxe_server('*', 55555, sub {

    # writer sends the buffer and calls back where
    # we are just closing connection

    ngxe_writer($_[0], 0, 1000, '', sub {
        return if $_[1]; # if there is an error connection will be closed
                         # internally after this callback

        ngxe_close($_[0]);
    });


    # autostart (NGXE_START) requires the handler be the last one
    # cuase it might call another handler (writer) which may not 
    # exist at the moment

    ngxe_reader($_[0], NGXE_START, 5000, sub {
        return if $_[1]; 

        # waiting for double CRLF in the read buffer

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
            } else {
                $_[3] = "HTTP/1.0 400 Bad Request\x0d\x0a".
                        "Content-type: text/html\x0d\x0a".
                        "\x0d\x0a".
                        "Bad Request\x0d\x0a";
            }

        } elsif (length($_[2]) > 2000) {
            $_[3] = "HTTP/1.0 400 Bad Request\x0d\x0a".
                    "Content-type: text/html\x0d\x0a".
                    "\x0d\x0a".
                    "Bad Request\x0d\x0a";
        } 

    });

});

ngxe_loop;




