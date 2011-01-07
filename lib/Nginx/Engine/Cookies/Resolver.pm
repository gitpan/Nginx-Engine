package Nginx::Engine::Cookies::Resolver;

use bytes;
use strict;
use warnings;

use Nginx::Engine;
use Net::DNS;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(ngxk_resolve);

use constant {
    # for both: reader and writer
    CONNECTION  => 0,  
    ERROR       => 1, 
    READBUF     => 2, 
    WRITEBUF    => 3, 
    MINLEN      => 4, # for reader only

    STATE       => 5, # extra argument for current reader's callback only
    DOMAIN      => 6,

    # states
    ST_MESSAGE_LENGTH  => 0,
    ST_MESSAGE_CONTENT => 1,
};


my @NAMESERVERS = (); 

# Looking for nameservers in /etc/resolv.conf or ~/.resolv.conf
# if exists.

my $resolv_conf = "/etc/resolv.conf";
   $resolv_conf = "$ENV{'HOME'}/.resolv.conf" if exists $ENV{'HOME'} && 
                                         -f "$ENV{'HOME'}/.resolv.conf";

if (-f $resolv_conf && open(FILE, $resolv_conf)) {
    while (<FILE>) {
        if (/^\s*nameserver\s+(\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3})/i) {
            push @NAMESERVERS, $1;
        }
    }
    close(FILE);
} 

# Using google's public nameserver if none found.
# It might be a security risk though. Issuing warning.

if (@NAMESERVERS == 0) {
    push @NAMESERVERS, '8.8.8.8';
    warn "[WARNING] No nameservers was found. ".
                   "Using $NAMESERVERS[-1] as an alternative.";
}



sub ngxk_resolve ($&;@) {

    my $r = [ $_[1], [ $_[0], 0, undef, @_[2..$#_] ] ];

    ngxe_client('*', $NAMESERVERS[0], 53, 1000, sub {

        # $_[0] == $_[CONNECTION] 
        # $_[1] == $_[ERROR] 
        # @_[2..$#_] - extra args placed after callback sub

        my $r = $_[2];

        if ($_[ERROR]) {
            $r->[1]->[1] = $_[ERROR];
            &{$r->[0]}(@{$r->[1]});
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

            if ($_[ERROR]) {
                my $r = $_[5];
                $r->[1]->[1] = $_[ERROR];
                &{$r->[0]}(@{$r->[1]});
                return;
            }


            if (length($_[2]) < 2) {
                $_[MINLEN] = 2;
                return;
            }

            my $len = unpack('n', substr($_[READBUF], 0, 2)) + 2;

            if (length($_[2]) < $len) {
                $_[MINLEN] = $len;
                return;
            }

            substr($_[READBUF], 0, 2, '');

            # Response received, extracting IP addresses
            # from the RRs.
            my ($rv, $ips) = ngxk_process_dns_packet($_[5], \$_[READBUF]);

            my $r = $_[5];
            $r->[1]->[1] = $rv;
            $r->[1]->[2] = $ips;
            &{$r->[0]}(@{$r->[1]});

            ngxe_close($_[CONNECTION]);

        }, $r); 


        # Creating DNS packet to send over TCP,
        my $packet = Net::DNS::Packet->new($r->[1]->[0]);
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
                my $r = $_[4];
                $r->[1]->[1] = $_[ERROR];
                &{$r->[0]}(@{$r->[1]});
                return;
            }

            # Writer automatically calls 
            #  ngxe_writer_stop($_[0]) if there is no data 
            # in the write buffer and if there is 
            # a reader - calls ngxe_reader_start($_[0]) as well

        }, $r);
    }, $r);
}


sub ngxk_process_dns_packet {
    my $r    = shift;
    my $pbuf = shift;
    my $name = $r->[1]->[0];

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

        return (0, $key);
    } elsif ($rcode eq 'MXDOMAIN') {
        return ($rcode, []);
    } else {
        return ($rcode, undef);
    }
}

1;
