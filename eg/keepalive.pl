#!/usr/bin/perl

use strict;
use warnings;

use Nginx::Engine;
use HTTP::Parser2::XS;
use Digest::MD5 qw(md5_hex);
use Data::Dumper;

my $ngxe_keepalive = {};

sub ngxe_eg_put ($$$&);
sub ngxe_eg_server ($&);
sub ngxe_keepalive_request ($$&);
sub ngxe_keepalive_client ($$$$&);

# 

ngxe_init "", 1024;

ngxe_eg_server ':55555', sub {

    # $_[0] - connection 
    # $_[1] - error indicator (should be)
    # $_[2] - parsed request
    # $_[3] - content

    my $r = $_[2];

    print "connection: $_[0]\n";

    if ($r->{'_uri'} eq '/foo') {
        return md5_hex($_[3]);
    } else {
        return 'fail';
    }
};

ngxe_eg_put '127.0.0.1:55555', '/foo', 'bar', sub {

    # $_[0] - should be connection of something like it
    # $_[1] - error indicator 
    # $_[2] - parsed response
    # $_[3] - content

    if ($_[1]) {
        print "response failed: $_[1]\n\n";
        return;
    }

    print "response\n".Dumper($_[2])."\n\n";
    print "content\n$_[3]\n\n";
};

ngxe_timeout_set 1000, sub {

    ngxe_eg_put '127.0.0.1:55555', '/foo', 'bar', sub {

        # $_[0] - should be connection of something like it
        # $_[1] - error indicator 
        # $_[2] - parsed response
        # $_[3] - content

        if ($_[1]) {
            print "response failed: $_[1]\n\n";
            return;
        }

        print "response\n".Dumper($_[2])."\n\n";
        print "content\n$_[3]\n\n";
    };

};

ngxe_loop;


sub ngxe_eg_put ($$$&) {
    my $addrport = $_[0];
    my $uri      = $_[1];
    my $content  = $_[2];
    my $cb       = $_[3];
    my $buf      = "PUT $uri HTTP/1.0\x0d\x0a".
                   "Host: $addrport\x0d\x0a".
                   "Connection: keep-alive\x0d\x0a".
                   "Content-length: ".length($content)."\x0d\x0a".
                   "\x0d\x0a".
                   $content;

    ngxe_keepalive_request $addrport, \$buf, sub { 
        &$cb(@_);
    };
}

sub ngxe_eg_server ($&) {
    my ($addr, $port) = split(':', $_[0], 2);
    my $cb = $_[1];

    ngxe_server $addr, $port, sub {
        my $c = $_[0];
        my $r = {};

        # warn "srv: $_[0]: new connection accepted from $_[1]\n";

        ngxe_writer $_[0], 0, 5000, '', sub {
            if ($_[1]) {
                # warn "srv-wrt: $_[0]: error \"$_[1]\"\n";
                return;
            }

            if ($r->{'_keepalive'}) {
                # warn "srv-wrt: $_[0]: sent, switching back to reader\n";
                %$r = ();
            } else {
                # warn "srv-wrt: $_[0]: sent, closing connection\n";
                ngxe_close $_[0]; 
            }
        };

        ngxe_reader $_[0], NXSTART, 5000, sub {
            if ($_[1]) {
                # warn "srv-rd: $_[0]: error \"$_[1]\"\n";
                return;
            }

            if (scalar(keys(%$r)) == 0) {
                my $rv = parse_http_request($_[2], $r);
                if ($rv == -1 || ($rv == -2 && length($_[2]) > 4000)) {
                    $_[3] = "HTTP/1.0 400 Bad Request\x0d\x0a".
                            "Content-type: text/html\x0d\x0a".
                            "\x0d\x0a".
                            "Bad Request\x0d\x0a";
                    # warn "srv-rd: $_[0]: bad request\n";
                    return;
                } elsif ($rv == -2) {
                    # warn "srv-rd: $_[0]: incomplete request\n";
                    return;
                }

                $_[2] = substr($_[2], $rv);
            }

            if (($r->{'_method'} eq 'PUT' || $r->{'_method'} eq 'POST') && 
                $r->{'_content_length'} && 
                length($_[2]) < $r->{'_content_length'})
            {
                if ($r->{'_content_length'} < 200000) {
                    $_[4] = $r->{'_content_length'};
                    # warn "srv-rd: $_[0]: incomplete content\n";
                    return;
                } else {
                    $r->{'_keepalive'} = 0;
                    my $content = "Request Entity Too Large";
                    $_[3] = "HTTP/1.0 413 Request Entity Too Large\x0d\x0a".
                            "Connection: close\x0d\x0a".
                            "Content-Length: ".length($content)."\x0d\x0a".
                            "Content-Type: text/html\x0d\x0a".
                            "\x0d\x0a".
                            $content;
                    # warn "srv-rd: $_[0]: content too large\n";
                    return;
                }
            }


            my $status  = '200 OK';
            # warn "srv-rd: $_[0]: callback\n";
            my $content = &$cb($_[0], undef, $r, $_[2]);

            $_[2] = '';

            # warn "srv-rd: $_[0]: sending response\n";
            $_[3] = "HTTP/1.0 $status\x0d\x0a".
                    ($r->{'_keepalive'} ? "Connection: keep-alive\x0d\x0a" 
                                        : "Connection: close\x0d\x0a").
                    "Cache-Control: no-cache\x0d\x0a".
                    "Pragma: no-cache\x0d\x0a".
                    "Content-Type: text/html\x0d\x0a".
                    "Content-Length: ".length($content)."\x0d\x0a".
                    "\x0d\x0a".
                    $content;


        };
    };
}

sub ngxe_keepalive_client ($$$$&) {
    my $buf = $_[3];
    my $cb  = $_[4];
    
    # warn "kc: $_[0], $_[1], $_[2], 5000\n";

    ngxe_client $_[0], $_[1], $_[2], 5000, sub {
        if ($_[1]) {
            # warn "clnt: $_[0]: connect failed, calling back\n";
            &$cb($_[0], $_[1]);
            return;
        }

        # warn "clnt: $_[0]: connected\n";

        my $r = {};

        ngxe_reader $_[0], 0, 5000, sub {
            if ($_[1]) {
                # warn "clnt-rd: $_[0]: read error, calling back\n";
                &$cb($_[0], $_[1]);
                return;
            }

            if (scalar(keys(%$r)) == 0) {
                my $rv = parse_http_response($_[2], $r);
                if ($rv == -1 || ($rv == -2 && length($_[2]) > 4096)) {
                    # warn "clnt-rd: $_[0]: bad response, calling back\n";
                    &$cb($_[0], $_[1]);
                    # warn "clnt-rd: $_[0]: closing connection\n";
                    ngxe_close $_[0];
                    return;
                } elsif ($rv == -2) {
                    return;
                }
                
                $_[2] = substr($_[2], $rv);
            }

            if ($r->{'_content_length'} && 
                length($_[2]) < $r->{'_content_length'}) 
            {
                $_[4] = $r->{'_content_length'};
                # warn "clnt-rd: $_[0]: waiting for more data\n";
                return;
            }

            ngxe_reader_stop $_[0];

            # warn "clnt-rd: $_[0]: reader stopped, calling back\n";
            &$cb($_[0], $_[1], $r, $_[2]);

            # warn "clnt-rd: $_[0]: cleaning up\n";
            $_[2] = '';
            %$r = ();
        };

        ngxe_writer $_[0], NXSTART, 5000, $buf, sub {
            if ($_[1]) {
                # warn "clnt-wrt: $_[0]: write error, calling back\n";
                &$cb($_[0], $_[1]);
                return;
            }

            # warn "clnt-wrt: $_[0]: request sent, waiting for response\n";
        };
    };

}

sub ngxe_keepalive_request ($$&) {
    my ($addrport, $buf, $cb) = @_[0..2];
    my ($addr, $port) = split(':', $addrport, 2);
    my $key = "$addr:$port"; 
    my $ka;      # keepalive slot
    my $queue;   # requests' queue
    my $kicker;  # anonymouse sub that starts the flow

    # Checking whether or not we have a slot
    # for keepalive connection in the global
    # $ngxe_keepalive hash.

    if ($ngxe_keepalive->{$key}) {
        # warn "kr: $key: found keepalive slot\n";
        $ka    = $ngxe_keepalive->{$key};
        $queue = $ka->[1];
    } else {
        # warn "kr: $key: creating new keepalive slot\n";
                 # [$connection, $queue, $availability, $tries]
        $ka    = [undef, [], 1, 0];
        $queue = $ka->[1];

        $ngxe_keepalive->{$key} = $ka; 
    }

    # Adding request and callback to the queue.

    push @$queue, [$buf, $cb];

    # We can't send the request if slot isn't
    # available. And since it's already queued
    # we just return.
    # $ka->[2] indicates availability of this 
    # keepalive slot.

    if (!$ka->[2]) {
        # warn "kr: $key: keepalive slot isn't free, request queued\n";
        return;
    }

    # If it is available and has a connection
    # than we can send our request. 

    if ($ka->[2] && $ka->[0]) {
        # warn "kr: $key: slot is free, sending request to $ka->[0]\n";

        # We are using this slot now, marking
        # it unavailable for next requests.

        $ka->[2] = 0;

        # Puting data into the writer's buffer
        # which in turn should send it, receive
        # response and call us ($kicker) back with 
        # the results.
        # $kicker defined later.

        ngxe_writer_put $ka->[0], $queue->[0]->[0];

        return;
    }

    # warn "kr: $key: slot is free, but doesn't have a connection\n";

    # At this point we know that slot is available
    # but there is no connection associated with it, 
    # i.e. no actual connection to the remote server.
    # So we need to make a connection, send request,
    # get response, call back, send another request
    # and so on.

    # Marking current slot unavailable.

    $ka->[2] = 0;

    # $kicker tries to make a connection and to send 
    # all requests one after another.

    $kicker = sub {

        # Keepalive client is a simple http client that
        # stops the reader whenever receives an entire
        # response. 

        ngxe_keepalive_client '*', $addr, $port, $buf, sub {

            # $_[1] indicates that some IO error occured.

            if ($_[1]) {

                # Reconnecting and trying again just once. 
                # $ka->[3] is counting our attempts.

                if (++$ka->[3] < 2) {
                    # warn "kr: $_[0]: connection failed, reconnecting\n";
                    &$kicker(); # calling itself
                    return;
                }

                # Reconnect failed.
                # Calling back to all waiting subs with error.

                # warn "kr: $_[0]: reconnect failed, calling back\n";
                while (@$queue) {
                    my $cb = $queue->[0]->[1];
                    shift @$queue;

                    &$cb(undef, $_[1], undef, undef);
                }

                # Cleaning up keepalive slot.Marking it available, 
                # clearing connection $ka->[0] and tries' counter.

                # Connection is closed and destroyed by the engine
                # on error. 

                $ka->[0] = undef; # connection
                $ka->[2] = 1;     # availability
                $ka->[3] = 0;     # tries 
                return;
            }

            # Request succeeded at this point.
            # Need to call back and send another request
            # if there is one.

            # Resetting tries' counter so we can reconnect
            # on failure rather than calling back right away.

            $ka->[3] = 0;

            # Associating connection with our keepalive slot.
            # This allows us to reuse it.

            $ka->[0] = $_[0];

            # Calling back. 

            # warn "kr: $_[0]: ok, calling back\n";
            my $cb = $queue->[0]->[1]; 
            shift @$queue;
            &$cb(undef, 0, $_[2], $_[3]);

            # If our queue isn't empty - sending another request
            # over the same connection.

            if (@$queue) {

                # Puting data into the writer's buffer
                # which in turn should send it, receive
                # response and call us ($kicker) back with 
                # the results.

                # warn "kr: $_[0]: sending next request\n";
                ngxe_writer_put $_[0], $queue->[0]->[0];

            } else {

                # No queued requests - simply making slot
                # available again. 

                # warn "kr: $_[0]: marking slot as available\n";
                $ka->[2] = 1;
            }
        };
    };

    &$kicker();
}


sub ngxe_keepalive_cleaner {

    # Going through the list of keepalive slots 
    # and closing unused connections. 

    foreach my $key (keys %$ngxe_keepalive) {
        my $ka = $ngxe_keepalive->{$key};

        if ($ka->[2] && $ka->[0]) {
            ngxe_close($ka->[0]);
            delete $ngxe_keepalive->{$key};
        }
    }
}



