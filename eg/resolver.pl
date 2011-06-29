#!/usr/bin/perl

=head1 NAME

resolver.pl - simple example of a TCP DNS resolver using Net::DNS

=head1 DESCRIPTION

Nginx::Engine lacks UDP support right now, so there is no usual UDP resolver,
but simple TCP resolver instead. Although with Net::DNS you probably won't 
even see the difference, you know how slow it is.

It was a separate package before, but I don't think it should be. 
Just copy needed parts of the code if you need it.

=cut

use strict;
use warnings;
use bytes;

use Nginx::Engine;
use Net::DNS;
use Data::Dumper;

sub ngxe_resolve ($$&;@);
sub ngxe_parse_dns_packet ($$);

ngxe_init '', 64;

ngxe_resolve "8.8.8.8", "google.com", sub {
    if ($_[1]) {
        warn "$_[0]: error: $_[1]\n";
        return;
    }

    print Dumper($_[0], $_[2]);
};

ngxe_loop;


sub ngxe_resolve ($$&;@) {
    my $ns     = $_[0];
    my $domain = $_[1];
    my $cb     = $_[2];
    my $cbargs = [ $_[1], 0, undef, @_[3..$#_] ];

    ngxe_client '*', $ns, 53, 5000, sub {

        if ($_[1]) { 
            $cbargs->[1] = $_[1];
            &$cb(@$cbargs);
            return;
        }

        ngxe_reader $_[0], 0, 30000, sub {

            # reader's callback:
            # $_[0] - connection
            # $_[1] - error indicator
            # $_[2] - read buffer
            # $_[3] - writer buffer
            # $_[4] - minlen, for how much data to wait (not precisely)
            # @_[5..$#_] - extra args placed after callback sub

            if ($_[1]) {
                $cbargs->[1] = $_[1];
                &$cb(@$cbargs);
                return;
            }

            # waiting for callback with more data
            if (length($_[2]) < 2) {
                return;
            }

            # now we know how long our packet is
            my $len = unpack('n', substr($_[2], 0, 2)) + 2;

            # if we don't have whole packet - waiting again
            if (length($_[2]) < $len) {
                $_[4] = $len; 
                return;
            }

            # removing length of the packet from the packet
            substr($_[2], 0, 2, ''); 

            # extracting IP addresses
            # from the RRs.

            my ($rv, $ips) = ngxe_parse_dns_packet($domain, \$_[2]);

            $cbargs->[1] = $rv;
            $cbargs->[2] = $ips;
            &$cb(@$cbargs);

            ngxe_close($_[0]);

        }; 


        # Starting writer might call the reader, so reader have
        # to be defined at this point.

        # Writer's timeout should be small for small packets,
        # it only indicates that data was send into the kernel's space.

        # Creating DNS packet to send over TCP,
        my $packet = Net::DNS::Packet->new($domain);
        my $msg = pack("n", length($packet->data)).$packet->data;

        # Creating writer with this packet in the write 
        # buffer and starting to send data.
        ngxe_writer $_[0], NGXE_START, 1000, $msg, sub {

            # writer's callback:
            # $_[0] - connection
            # $_[1] - error indicator
            # $_[2] - read buffer
            # $_[3] - writer buffer
            # @_[4..$#_] - extra args placed after callback sub

            if ($_[1]) {
                $cbargs->[1] = $_[1];
                &$cb(@$cbargs);
                return;
            }

            # Writer automatically calls 
            #  ngxe_writer_stop($_[0]) if there is no data 
            # in the write buffer and if there is 
            # a reader - calls ngxe_reader_start($_[0]) as well.
            # Does nothing if you added some data to the write
            # buffer.
        };
    };
}


sub ngxe_parse_dns_packet ($$) {
    my $name = $_[0];
    my $pbuf = $_[1];

    my ($packet, $error) = Net::DNS::Packet->new($pbuf);
    my $rcode = '';

    $rcode = $packet->header->rcode if $packet;

    # Net::DNS makes anything ugly and messy, don't look there

    if ($rcode eq 'NOERROR') { 
        my %RECS = ();
        foreach my $rr ($packet->answer) {
            if ($rr->type eq 'CNAME') {
                $RECS{$rr->name} = $rr->cname;
            } elsif ($rr->type eq 'A') {
                if (!exists $RECS{$rr->name}) {
                    $RECS{$rr->name} = [];
                }

                push @{$RECS{$rr->name}}, $rr->address;
            }
        }

        my $key = $name;
        while (exists $RECS{$key}) {
            my $old = $key;
            $key = $RECS{$key};
            delete $RECS{$old};
            last if ref $key eq 'ARRAY';
        }

        return (0, $key);
    } elsif ($rcode eq 'MXDOMAIN') {
        return ($rcode, []);
    } else {
        return ($rcode, undef);
    }
}

=head1 SEE ALSO

L<Nginx::Engine>

=head1 AUTHOR

Alexandr Gomoliako <zzz@zzz.org.ua>

=cut

