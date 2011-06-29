#!/usr/bin/perl

use strict;
use warnings;
use bytes; # It should not be needed in general,
           # but forces length() to use bytes instead
           # of characters and can be useful for
           # generating Content-Length for UTF-8 data
           # and stuff like that.

use Nginx::Engine;

ngxe_init "", 4096;

ngxe_server '*', 55555, sub {

    # writer sends the buffer and calls back where
    # we are just closing connection

    ngxe_writer $_[0], 0, 1000, '', sub {
        return if $_[1]; # if there is an error - connection will be closed
                         # internally after the callback

        ngxe_close $_[0]; # forcing writer to stop and destroy connection
    };


    # autostart (NXSTART or 1) requires the reader to be the last one
    # becuase it might call a writer which may not exist at the moment

    ngxe_reader $_[0], NXSTART, 5000, sub {
        return if $_[1]; 

        my $uri = '';
        if ($_[2] =~ /^GET\s+([^\s]+)/) {
            $uri = $1;
        } 
        
        if ($_[2] !~ /\x0d?\x0a\x0d?\x0a/) {
            if (length($_[2]) > 2000) {
                $_[3] = "HTTP/1.0 400 Bad Request\x0d\x0a".
                        "Content-type: text/html\x0d\x0a".
                        "\x0d\x0a".
                        "Bad Request\x0d\x0a";
            } 
            return;
        }

        $_[2] = ''; # If you want to implement keepalive 
                    # you need to clear reader's buffer.
                    # Only writer's buffer is cleared 
                    # automatically after it's done.

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
    };
};

ngxe_loop;


