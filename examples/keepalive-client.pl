#!/usr/bin/perl

use bytes;
use strict;
use warnings;

use Nginx::Engine;

# Keeping connection alive is easy. Just return from the writer 
# without calling ngxe_close() or from the reader, depengig on your
# application. But this isn't very useful. 
# 
# To make it useful we need another layer of abstraction, i.e. 
# subroutine you can call to send or get something from remote 
# machine. This way we can do whatever we want and call back
# with the results.
# 

use constant {
    KA_CONNECTION => 0,
    KA_BUFFER     => 1,
    KA_CB         => 2,
    KA_CBARGS     => 3,
    KA_TRIES      => 4,
};

my @KA_CLIENT    = ('*', '65.55.21.250', 80, 1000); 
my @KA_AVAILABLE = ();

ngxe_init("", 256);


ngxe_interval_set(1000, sub { 

    my $buf = "GET /robots.txt HTTP/1.0\x0d\x0a".
              "Host: www.microsoft.com\x0d\x0a".
              "Connection: keep-alive\x0d\x0a".
              "\x0d\x0a";

    ka_request($buf, sub {

        if (defined $_[0]) {
            print "response received: \n'$_[0]'\n\n\n";
        } else {
            print "error: undef received\n\n\n";
        }
    });

});

ngxe_loop;

sub ka_request ($&;@) {
    my ($buf, $cb) = @_[0,1];
    my $cbargs     = [ @_[2..$#_] ];

    # checking if we have available connections
    # to send request to 

    if (@KA_AVAILABLE) {

        # obtaining the most recent keepalive entity
        my $ka = pop @KA_AVAILABLE;

        $ka->[KA_BUFFER] = $buf;
        $ka->[KA_CB]     = $cb;
        $ka->[KA_CBARGS] = $cbargs;
        $ka->[KA_TRIES]  = 0;

        warn "$ka->[KA_CONNECTION]: available\n";

        # setting writer buffer will automatically
        # restart the wrtier

        ngxe_writer_buffer_set($ka->[KA_CONNECTION], $ka->[KA_BUFFER]);

    } else {

        # creating new keepalive connection entity

        my $ka = [];

        $ka->[KA_BUFFER] = $buf;
        $ka->[KA_CB]     = $cb;
        $ka->[KA_CBARGS] = $cbargs;
        $ka->[KA_TRIES]  = 0;

        warn "no connections available right now, creating new one\n";

        ngxe_client(@KA_CLIENT, \&ka_client_cb, $ka);
    }
}


sub ka_client_cb {
    my ($c, $error, $ka) = @_;

    if ($error) {
        warn "cannot connect\n";

        my $cb     = $ka->[KA_CB];
        my $cbargs = $ka->[KA_CBARGS];

        &$cb(undef, @$cbargs);
        return;
    }

    warn "$c: connected\n";

    if ($ka->[KA_TRIES]++ >= 2) {

        warn "$c: connected\n";

        my $cb     = $ka->[KA_CB];
        my $cbargs = $ka->[KA_CBARGS];

        ngxe_close($c);

        &$cb(undef, @$cbargs);
        return;
    }

    ngxe_reader($c, 0, 1000, sub {
        my ($c, $error, $ka) = @_[0,1,5,6];

        if ($error) {
            warn "$c: read failed\n";

            ngxe_client(@KA_CLIENT, \&ka_client_cb, $ka);
            return;
        }

        warn "$c: read ".length($_[2])." bytes\n";

        # header
        if (!$_[6] && $_[2] =~ /\x0d?\x0a\x0d?\x0a/g) {
            my $len = pos($_[2]);
            $_[6] = 1;

            warn "$c: len = $len\n";

            if ($_[2] =~ /Content-length:\s*(\d+)/i) {
                warn "$c: c_len = $1\n";

                if (length($_[2]) - $len < $1) {
                    $_[4] = $1 + $len;

                    warn "$c: waiting for $_[4] bytes in the buffer\n";
                    return;
                }
            }
        }

        $_[6] = 0;

        my $cb     = $ka->[KA_CB];
        my $cbargs = $ka->[KA_CBARGS];

        &$cb($_[2], @$cbargs);

        # stops the reader
        ngxe_reader_stop($c);

        # at this point we don't have any events
        # assosiated with neither reader nor writer
        # and can do whatever we want and then restart 
        # either reader or writer

        # making this connection available for new requests

        $ka->[KA_CONNECTION] = $c;
        $ka->[KA_TRIES]      = 0;

        undef $ka->[KA_BUFFER];
        undef $ka->[KA_CB];
        undef $ka->[KA_CBARGS];
        
        push @KA_AVAILABLE, $ka;

    }, $ka, 0);

    ngxe_writer($c, NGXE_START, 1000, $ka->[KA_BUFFER], sub {
        my ($c, $error, $ka) = @_[0,1,4];

        if ($error) {
            warn "$c: write failed\n";

            ngxe_client(@KA_CLIENT, \&ka_client_cb, $ka);
            return;
        }

        warn "$c: write done\n";

        $_[2] = ''; # clearing read buffer

    }, $ka);

}


