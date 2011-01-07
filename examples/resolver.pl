#!/usr/bin/perl

use bytes;
use strict;
use warnings;

use Nginx::Engine;
use Net::DNS;

# Internal resolver isn't implemented just yet, so this one might
# be needed. And it shows how to create s imple stateful reader.
# 
# Resolver connects to the public DNS server over TCP and tries 
# to resolve each domain name.
# 


# Using constants to make complex code a bit more readable.
# It's really easy to make a mistake if every scalar is just
# a number. 
use constant {
    # for both: reader and writer
    CONNECTION  => 0,  
    ERROR       => 1, 
    READBUF     => 2, 
    WRITEBUF    => 3, 
    MINLEN      => 4, # for reader only

    STATE       => 5, # extra argument for current reader's callback only

    # states
    ST_MESSAGE_LENGTH  => 0,
    ST_MESSAGE_CONTENT => 1,
};


ngxe_init("", 256);

my $resolver_ip   = '8.8.8.8';
my $resolver_port = '53';

my @LIST = qw(google.com
              nginx.org
              www.cpan.org
              cpan.org);

# Creating concurrent requests to single DNS server, 
# Be careful with that.
foreach (@LIST) {

    ngxe_client('*', $resolver_ip, $resolver_port, 1000, sub {

        # $_[0] == $_[CONNECTION] 
        # $_[1] == $_[ERROR] 
        # @_[2..$#_] - extra args placed after callback sub

        # $_[2] is the name of the domain to resolve

        my $name = $_[2];

        if ($_[ERROR]) {
            warn "$_[2]:\nconnect failed\n";
            return;
        }

        ngxe_reader($_[CONNECTION], 0, 30000, sub {

            # reader's callback:
            # $_[0] == $_[CONNECTION] 
            # $_[1] == $_[ERROR] 
            # $_[2] == $_[READBUF] 
            # $_[3] == $_[WRITEBUF] 
            # $_[4] == $_[MINLEN] - minimum amount of data to read
            #                       to callback with, resets to 0 every time
            # @_[5..$#_] - extra args placed after callback sub

            # in this case $_[5] is the state and 
            #  $_[6] is the name of the domain we are resolving

            if ($_[ERROR]) {
                warn "$_[6]:\nread failed\n";
                return;
            }

            while (1) {

                if ($_[STATE] == ST_MESSAGE_LENGTH) {

                    # we got there with less than 
                    # length of the message length,
                    # need to wait it out
                    if (length($_[2]) < 2) {
                        $_[MINLEN] = 2;
                        return;
                    }

                    # have len, next state is the content no matter what
                    $_[STATE] = ST_MESSAGE_CONTENT;

                    # DNS responses over TCP has unsigned short
                    # length in front of the message
                    my $len = unpack('n', substr($_[READBUF], 0, 2, ''));

                    if (length($_[2]) < $len) {
                        # read $len bytes firsth
                        # and to the next state on next callback
                        $_[MINLEN] = $len;
                        return;
                    } else {
                        # next state right now, we have 
                        # all the data we need
                        next; 
                    }

                } elsif ($_[STATE] == ST_MESSAGE_CONTENT) {

                    # Response received, extracting IP addresses
                    # from the RRs.
                    my (@IPs) = process_dns_packet($_[6], \$_[READBUF]);

                    print "$_[6]:\n    ".join("\n    ", @IPs)."\n";
                    ngxe_close($_[CONNECTION]);
                    return;
                } else {

                    warn "this error cannot happed, magic?";
                    ngxe_close($_[CONNECTION]);
                    return;
                }
            }

        }, ST_MESSAGE_LENGTH, $name); # initial state


        # Creating DNS packet to send over TCP,
        my $packet = Net::DNS::Packet->new($name);
        my $msg = pack("n", length($packet->data)).$packet->data;

        # Creating writer with this packet in the write 
        # buffer and starting to send data.
        ngxe_writer($_[CONNECTION], NGXE_START, 1000, $msg, sub {

            # writer's callback:
            # $_[0] == $_[CONNECTION] 
            # $_[1] == $_[ERROR] 
            # $_[2] == $_[READBUF] 
            # $_[3] == $_[WRITEBUF] 
            # @_[4..$#_] - extra args placed after callback sub

            # in this case $_[4] is the name of the domain we are resolving

            if ($_[ERROR]) {
                warn "$_[4]:\nwrite failed\n";
                return;
            }

            # Writer automatically calls 
            #  ngxe_writer_stop($_[0]) if there is no data 
            # in the write buffer and if there is 
            # a reader - calls ngxe_reader_start($_[0]) as well

        }, $name);
    }, $_);
}

ngxe_loop;


sub process_dns_packet {
    my $name = shift;
    my $pbuf = shift;

    my ($packet, $error) = Net::DNS::Packet->new($pbuf);
    my $rcode = '';

    $rcode = $packet->header->rcode if $packet;

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

        return @$key;
    } elsif ($rcode eq 'MXDOMAIN') {
        return ();
    } else {
        return ();
    }
}

