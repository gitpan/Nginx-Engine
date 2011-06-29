package Nginx::Engine::PP;

use strict;
use warnings;
use bytes;

use IO::Socket;
use Socket qw(inet_aton inet_ntoa);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use Nginx::Engine::Const;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(

    ngxe_init
    ngxe_reader_init_buffer_size

    ngxe_timeout_set
    ngxe_timeout_clear

    ngxe_interval_set
    ngxe_interval_clear

    ngxe_server

    ngxe_client

    ngxe_reader
    ngxe_reader_start
    ngxe_reader_stop
    ngxe_reader_stop_writer_start
    ngxe_reader_timeout

    ngxe_writer
    ngxe_writer_start
    ngxe_writer_stop
    ngxe_writer_stop_reader_start
    ngxe_writer_timeout
    ngxe_writer_buffer_set
    ngxe_writer_put

    ngxe_close

    ngxe_loop

    ngxe_buf
    ngxe_buffree

    ngxe_pp_printbufstats

    NGXE_START
    NXSTART
    NXRVBUF
);

our $VERSION = '0.02';

use constant {
    CN_ID         => 0, CN_FILENO => 0,
    CN_FH         => 1,
    CN_READ       => 2,
    CN_WRITE      => 3,
    CN_RBUF       => 4,
    CN_WBUF       => 5,
    CN_RMAX       => 6,
    CN_WOFF       => 7,
    CN_WIND       => 8,
    CN_REMOTEADDR => 9,
    CN_CLOSED     => 10,

    CEV_TYPE      => 0, 
    CEV_TIMEOUT   => 1,
    CEV_TIMEOUTAT => 2,
    CEV_CALLBACK  => 3,
    CEV_ARGS      => 4,

    CEVT_READ     => 1,
    CEVT_ACCEPT   => 2,
    CEVT_WRITE    => 3,
    CEVT_CONNECT  => 4,
};


our $NOPUSHBACK = 0;

our $NGXE_BUFSIZE = 32768;

my $quit = 0;

my @XBUFSPOOL    = ();
my $XBUFSINUSE   = 0;
my $XBUFSFREE    = 0;
my $XBUFSREUSED  = 0;
my $XBUFSCREATED = 0;

my @BUFSPOOL    = ();
my $BUFSINUSE   = 0;
my $BUFSFREE    = 0;
my $BUFSREUSED  = 0;
my $BUFSCREATED = 0;


my %FDSET;
my %CONN;
my @TIMERS;
my $rin  = '';
my $win  = '';
my $rout = '';
my $wout = '';


sub ngxe_init {
    no warnings 'signal';
    $SIG{'PIPE'} = 'IGNORE';

    if (defined $_[2]) {
        $NGXE_BUFSIZE = int($_[2]);
    }
}

sub ngxe_reader_init_buffer_size ($) {
    $NGXE_BUFSIZE = $_[0];
}

sub ngxe_pp_printbufstats {

    my $xbufspool = scalar @XBUFSPOOL;
    my $bufspool = scalar @BUFSPOOL;

    print << "    END";

    xbufspool     $xbufspool
    XBUFSINUSE    $XBUFSINUSE
    XBUFSFREE     $XBUFSFREE
    XBUFSREUSED   $XBUFSREUSED
    XBUFSCREATED  $XBUFSCREATED

    bufspool      $bufspool
    BUFSINUSE     $BUFSINUSE
    BUFSFREE      $BUFSFREE
    BUFSREUSED    $BUFSREUSED
    BUFSCREATED   $BUFSCREATED

    END
}

sub ngxe_xbuf (;$) {

    if (@XBUFSPOOL) {
        $XBUFSFREE--;
        $XBUFSINUSE++;
        $XBUFSREUSED++;

        my $buf = pop @XBUFSPOOL;
          $$buf = defined $_[0] ? $_[0] : '';
        return $buf;
    } else {
        $XBUFSCREATED++;
        $XBUFSINUSE++;

        my $bu  = ""; # "\0" x $NGXE_BUFSIZE; 
        my $buf = \$bu;
          $$buf = defined $_[0] ? $_[0] : '';

        return $buf;
    }
}

sub ngxe_xbuffree ($) {
    push @XBUFSPOOL, $_[0];
    $XBUFSFREE++;
    $XBUFSINUSE--;
}

sub ngxe_buf (;$) {
    # argument is ignored in pure-perl implementation

    if (@BUFSPOOL) {
        $BUFSFREE--;
        $BUFSINUSE++;
        $BUFSREUSED++;

        my $buf = pop @BUFSPOOL;
          $$buf = '';
        return $buf;
    } else {
        $BUFSCREATED++;
        $BUFSINUSE++;

        my $bu  = ""; # "\0" x $NGXE_BUFSIZE; 
        my $buf = \$bu;
          $$buf = '';

        bless $buf, 'Nginx::Engine::PP::Buf';
        return $buf;
    }
}

sub ngxe_buffree ($) {
    undef $_[0];
}



sub _timer_put {
    my $tev = shift;

    my $i = 0;
    while ($i <= $#TIMERS && $TIMERS[$i]->[0] < $tev->[0]) {
        $i++;
    }

    splice(@TIMERS, $i, 0, $tev);
}

sub _timer_del {
    my $tev = shift;

    for my $i (0 .. $#TIMERS) {
        if ($TIMERS[$i] eq $tev) {
            $TIMERS[$i] = undef;
            last;
        }
    }
}


sub ngxe_timeout_set ($$;@) {
    my $tev = [time + int(($_[0] + 500)/1000), undef, $_[1], [@_[2..$#_]]];
    _timer_put($tev);
    return $tev;
}

sub ngxe_timeout_clear ($) {
    _timer_del($_[0]);
}

sub ngxe_interval_set ($$;@) {
    my $dt  = int(($_[0] + 500)/1000);
    my $tev = [time + $dt, $dt, $_[1], [@_[2..$#_]]];
    _timer_put($tev);
    return $tev;
}

sub ngxe_interval_clear ($) {
    _timer_del($_[0]);
}

sub timestr { 
    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = @_;
    $year += 1900;
    $mon++;
    return sprintf("$year-%02i-%02i %02i:%02i:%02i", 
                   $mon, $mday, $hour, $min, $sec);
}



sub ngxe_loop {

    sub quit { $quit = 1; }
    local $SIG{'INT'}  = \&quit;
    local $SIG{'QUIT'} = \&quit;
    local $SIG{'TERM'} = \&quit;
    local $SIG{'KILL'} = \&quit;

    while (!$quit) {
        ($rout, $wout) = ('', '');

        my $n = select($rout = $rin, $wout = $win, '', 1);

        if (defined $n && $n == -1) {
            unless ($!{EINTR}) {
                die "[".timestr(localtime(time))."] ".
                    "[ERROR] select(): $!\n";
            }
        }

        my $t = time;

        while (my ($fno, $c) = each %FDSET) {

            my $rev = $c->[CN_READ];
            my $wev = $c->[CN_WRITE];

            if (vec($rout, $fno, 1) == 1 && defined $rev) {

                if ($rev->[CEV_TYPE] == CEVT_READ) {
                    _read($c);
                } elsif ($rev->[CEV_TYPE] == CEVT_ACCEPT) {
                    _accept($c);
                }

            } elsif (vec($rin, $fno, 1) == 1 && 
                     defined $rev && $rev->[CEV_TIMEOUT] && 
                     defined $rev->[CEV_TIMEOUTAT] &&
                     $rev->[CEV_TIMEOUTAT] <= $t) {

                _timedout($c, $rev);
                next;
            }

            if (vec($wout, $fno, 1) == 1 && defined $wev) {

                if ($wev->[CEV_TYPE] == CEVT_WRITE) {
                    _write($c);
                } elsif ($wev->[CEV_TYPE] == CEVT_CONNECT) {
                    _connect($c);
                }

            } elsif (vec($win, $fno, 1) == 1 && 
                     defined $wev && $wev->[CEV_TIMEOUT] && 
                     defined $wev->[CEV_TIMEOUTAT] &&
                     $wev->[CEV_TIMEOUTAT] <= $t) {

                _timedout($c, $wev);
                next;
            }
        }

        $t = time;

        # processing timers
        while (@TIMERS) {
            if (!defined $TIMERS[0]) {
                shift @TIMERS;
                next;
            } elsif ($TIMERS[0]->[0] > $t) {
                last;
            }

            my $tev = shift @TIMERS;
            if (defined $tev->[1] && $tev->[1] > 0) {
                $tev->[0] = $t + $tev->[1];
                _timer_put($tev);
            }

            &{$tev->[2]}($tev, @{$tev->[3]});
        }
    }
}

sub ngxe_reader_stop ($) {
    vec($rin,  $_[0]->[CN_FILENO], 1) = 0;
    vec($rout, $_[0]->[CN_FILENO], 1) = 0;
}

sub ngxe_reader_start ($;$) {
    vec($rin,  $_[0]->[CN_FILENO], 1) = 1;
    vec($rout, $_[0]->[CN_FILENO], 1) = 0;

    my $rev = $_[0]->[CN_READ];
    $rev->[CEV_TIMEOUT]   = $_[1] if defined $_[1];
    $rev->[CEV_TIMEOUTAT] = time + $rev->[CEV_TIMEOUT];
}

sub ngxe_writer_stop ($) {
    vec($win,  $_[0]->[CN_FILENO], 1) = 0;
    vec($wout, $_[0]->[CN_FILENO], 1) = 0;
}

sub ngxe_writer_start ($;$) {
    vec($win,  $_[0]->[CN_FILENO], 1) = 1;
    vec($wout, $_[0]->[CN_FILENO], 1) = 1;

    my $wev = $_[0]->[CN_WRITE];
    $wev->[CEV_TIMEOUT]   = $_[1] if defined $_[1];
    $wev->[CEV_TIMEOUTAT] = time + $wev->[CEV_TIMEOUT];

    _write($_[0]);
}

sub ngxe_reader_stop_writer_start ($) {
    vec($rin,  $_[0]->[CN_FILENO], 1) = 0;
    vec($rout, $_[0]->[CN_FILENO], 1) = 0;
    vec($win,  $_[0]->[CN_FILENO], 1) = 1;
    vec($wout, $_[0]->[CN_FILENO], 1) = 1;

    my $wev = $_[0]->[CN_WRITE];
    $wev->[CEV_TIMEOUTAT] = time + $wev->[CEV_TIMEOUT];

    _write($_[0]);
}

sub ngxe_writer_stop_reader_start ($) {
    vec($rin,  $_[0]->[CN_FILENO], 1) = 1;
    vec($rout, $_[0]->[CN_FILENO], 1) = 0;
    vec($win,  $_[0]->[CN_FILENO], 1) = 0;
    vec($wout, $_[0]->[CN_FILENO], 1) = 0;

    my $rev = $_[0]->[CN_READ];
    $rev->[CEV_TIMEOUTAT] = time + $rev->[CEV_TIMEOUT];
}

sub ngxe_writer_timeout ($;$) {
    my $wev = $_[0]->[CN_WRITE];
    my $rv  = $wev->[CEV_TIMEOUT];

    $wev->[CEV_TIMEOUT] = $_[1] if defined $_[1];

    return $rv;
}

sub ngxe_reader_timeout ($;$) {
    my $rev = $_[0]->[CN_READ];
    my $rv  = $rev->[CEV_TIMEOUT];

    $rev->[CEV_TIMEOUT] = $_[1] if defined $_[1];

    return $rv;
}

sub ngxe_writer_buffer_set ($$) {
    ${$_[0]->[CN_WBUF]} = $_[1];

    ngxe_writer_start($_[0]);
}

*ngxe_writer_put = \&ngxe_writer_buffer_set;


sub ngxe_server ($$$;@) {
    # $addr, $port, $cb, ...

    my $fh = IO::Socket::INET->new(Listen    => 4096,
                                   ReuseAddr => 1,
                                   LocalAddr => $_[0] eq '*' ? '' : $_[0],
                                   LocalPort => $_[1],
                                   Blocking  => 0,
                                   Proto     => 'tcp') || return undef;
    my $fno = fileno($fh);

    my $c   = [];
    my $rev = [];

    $rev->[CEV_TYPE]     = CEVT_ACCEPT;
    $rev->[CEV_CALLBACK] = $_[2];
    $rev->[CEV_ARGS]     = [@_[3..$#_]];

    $c->[CN_ID]    = $fno;
    $c->[CN_FH]    = $fh;
    $c->[CN_READ]  = $rev;
    $c->[CN_WRITE] = undef;

    $CONN{$fno} = $c;

    vec($rin, $fno, 1) = 1;
    $FDSET{$fno} = $c;

    return $c;
}

sub _accept {

    while (my $addr = accept(my $fh, $_[0]->[CN_FH])) {
        next if !defined fileno($fh) || !$addr;

        my ($p, $h) = sockaddr_in($addr); $h = inet_ntoa($h);

        if ($^O eq 'linux') {
            my $flags = fcntl($fh, F_GETFL, 0);
               $flags = fcntl($fh, F_SETFL, $flags | O_NONBLOCK);
        }

        my $cb   = $_[0]->[CN_READ]->[CEV_CALLBACK];
        my $args = $_[0]->[CN_READ]->[CEV_ARGS];
    
        my $fno = fileno($fh);
        my $c   = [];

        $c->[CN_ID]    = $fno;
        $c->[CN_FH]    = $fh;
        $c->[CN_READ]  = undef;
        $c->[CN_WRITE] = undef;

        $CONN{$fno}  = $c;
        $FDSET{$fno} = $c;
    
        &$cb($c, $h, @$args);
    }
}


sub ngxe_reader ($$$$;@) {
    # $c, $flags, $timeout, $cb, $args
    my $c   = $_[0];
    my $rev = [];

    $c->[CN_READ] = $rev;
    $c->[CN_RBUF] = ngxe_xbuf() if !defined $c->[CN_RBUF];
    $c->[CN_WBUF] = ngxe_xbuf() if !defined $c->[CN_WBUF];
    $c->[CN_RMAX] = undef;
    $c->[CN_WOFF] = 0;
    $c->[CN_WIND] = 0;

    $rev->[CEV_TIMEOUT]   = int(($_[2] + 500)/1000);
    $rev->[CEV_TIMEOUTAT] = time + $rev->[CEV_TIMEOUT];
    $rev->[CEV_TYPE]      = CEVT_READ;
    $rev->[CEV_CALLBACK]  = $_[3];
    $rev->[CEV_ARGS]      = [@_[4..$#_]];  

    if ($_[1] & NGXE_START) {
        ngxe_reader_start($c);
    }
}

sub _read {
    my $c     = $_[0];
    my $fh    = $_[0]->[CN_FH];
    my $buf   = $_[0]->[CN_RBUF];
#     my $size  = defined $_[0]->[CN_RMAX] && $_[0]->[CN_RMAX] <= $NGXE_BUFSIZE
#                     ? $_[0]->[CN_RMAX] : $NGXE_BUFSIZE;

    # ignoring buffer size completely
#     my $size  = defined $_[0]->[CN_RMAX] ? $_[0]->[CN_RMAX] : $NGXE_BUFSIZE;
    my $size  = defined $_[0]->[CN_RMAX] ? $_[0]->[CN_RMAX] : 0;

    my $total = length($$buf);
    my $error = 0;
    my $eof   = 0;

    while ($size == 0 || $total < $size) {
        my $len = sysread($fh, $$buf, $size ? $size - $total : 32768, 
                                                            length($$buf));

        if (!defined $len) {
            if ($!{EAGAIN} || $!{EWOULDBLOCK}) {
                last;
            } elsif ($!{EINTR}) {
                next;
            } else {
                $error = 1;
                last;
            }
        } elsif ($len == 0) {
            $eof   = 1;
            $error = 2;
            last;
        }

        $total += $len;
    }

    if (!$error && $total == 0) {
        return;
    }

    my $rev  = $_[0]->[CN_READ];
    my $cb   = $rev->[CEV_CALLBACK];
    my $args = $rev->[CEV_ARGS];
    my $err  = $error; # protecting $error from modification

    $rev->[CEV_TIMEOUTAT] = time + $rev->[CEV_TIMEOUT];

    if ($total > 0) {
        &$cb($c, 0, ${$c->[CN_RBUF]}, ${$c->[CN_WBUF]}, $c->[CN_RMAX], @$args);
    }

    if ($error || $eof) {
        &$cb($c, $err, ${$c->[CN_RBUF]}, ${$c->[CN_WBUF]}, $c->[CN_RMAX], 
             @$args);
    }

    if ($_[0]->[CN_CLOSED]) {
        return;
    }

    if ($error) {
        ngxe_close($_[0]);
    } elsif (
        vec($rout, $_[0]->[CN_FILENO], 1) == 1 && (
            ( 
                (
                    ref $_[0]->[CN_WBUF] eq 'SCALAR' || 
                    ref $_[0]->[CN_WBUF] eq 'Nginx::Engine::PP::Buf' 
                ) && length(${$_[0]->[CN_WBUF]}) > 0 
            ) || (
                ref $_[0]->[CN_WBUF] eq 'REF' && (
                    ref ${$_[0]->[CN_WBUF]} eq 'SCALAR' ||
                    ref ${$_[0]->[CN_WBUF]} eq 'Nginx::Engine::PP::Buf'
                )
            ) || (
                ref $_[0]->[CN_WBUF] eq 'REF' && (
                    ref ${$_[0]->[CN_WBUF]} eq 'Nginx::Engine::PP::Bufarray' ||
                    ref ${$_[0]->[CN_WBUF]} eq 'ARRAY'
                )
            )
        )
    ) 
    {
        $_[0]->[CN_WIND] = 0;
        $_[0]->[CN_WOFF] = 0;

        ngxe_reader_stop_writer_start($_[0]);
    }

}







sub _timedout {
    my $c    = $_[0];
    my $ev   = $_[1];
    my $type = $ev->[CEV_TYPE];

    if ($type == CEVT_READ) { 
        &{$ev->[CEV_CALLBACK]}($c, -1, ${$c->[CN_RBUF]}, ${$c->[CN_WBUF]}, 
                               $c->[CN_RMAX], @{$ev->[CEV_ARGS]});
    } elsif ($type == CEVT_WRITE) {
        &{$ev->[CEV_CALLBACK]}($c, -1, ${$c->[CN_RBUF]}, ${$c->[CN_WBUF]}, 
                               @{$ev->[CEV_ARGS]});
    } elsif ($type == CEVT_CONNECT) {
        &{$ev->[CEV_CALLBACK]}($c, -1, @{$ev->[CEV_ARGS]});
    }

    ngxe_close($_[0]);
}


sub ngxe_close ($) {

    if ($_[0]->[CN_CLOSED]) {
        return;
    }

    if (defined $_[0]->[CN_RBUF]) {
        ngxe_xbuffree($_[0]->[CN_RBUF]);
        delete $_[0]->[CN_RBUF];
    }

    if (defined $_[0]->[CN_WBUF]) {
        ngxe_xbuffree($_[0]->[CN_WBUF]);
        delete $_[0]->[CN_WBUF];
    }

    vec($rin,  $_[0]->[CN_FILENO], 1) = 0;
    vec($rout, $_[0]->[CN_FILENO], 1) = 0;
    vec($win,  $_[0]->[CN_FILENO], 1) = 0;
    vec($wout, $_[0]->[CN_FILENO], 1) = 0;

    close($_[0]->[CN_FH]);

    my $c = $_[0];

    delete $FDSET{$_[0]->[CN_FILENO]};
    delete $CONN{$_[0]->[CN_FILENO]};

    undef $c->[CN_FH];
    undef $c->[CN_FILENO];
    undef $c->[CN_READ];
    undef $c->[CN_WRITE];

    $c->[CN_CLOSED] = 1;

}





sub ngxe_writer ($$$$$;@) {
    # $c, $flags, $timeout, $buf, $cb, $args
    my $c   = $_[0];
    my $wev = [];

    $c->[CN_WRITE] = $wev;
    $c->[CN_RBUF]  = ngxe_xbuf() if !defined $c->[CN_RBUF];
    $c->[CN_WBUF]  = ngxe_xbuf() if !defined $c->[CN_WBUF];
    $c->[CN_RMAX]  = undef;
    $c->[CN_WOFF]  = 0;
    $c->[CN_WIND]  = 0;

    ${$c->[CN_WBUF]} = $_[3];

    $wev->[CEV_TIMEOUT]   = int(($_[2] + 500)/1000);
    $wev->[CEV_TIMEOUTAT] = time + $wev->[CEV_TIMEOUT];
    $wev->[CEV_TYPE]      = CEVT_WRITE;
    $wev->[CEV_CALLBACK]  = $_[4];
    $wev->[CEV_ARGS]      = [@_[5..$#_]];  

    if ($_[1] & NGXE_START) {
        ngxe_writer_start($c);
    }
}




sub _write {
    my $c      = $_[0];
    my $fh     = $_[0]->[CN_FH];

    my $autoempty = 0;
    my $buffers;

    if ((ref $_[0]->[CN_WBUF] eq 'SCALAR' ||
         ref $_[0]->[CN_WBUF] eq 'Nginx::Engine::PP::Buf')) {

        $buffers = [$_[0]->[CN_WBUF]];
        $autoempty = 1;
        $_[0]->[CN_WIND] = 0;

    } elsif (ref $_[0]->[CN_WBUF] eq 'REF' && 
             (ref ${$_[0]->[CN_WBUF]} eq 'SCALAR' ||
              ref ${$_[0]->[CN_WBUF]} eq 'Nginx::Engine::PP::Buf')) {

        $buffers = [${$_[0]->[CN_WBUF]}];
        $_[0]->[CN_WIND] = 0;

    } elsif (ref $_[0]->[CN_WBUF] eq 'REF' && 
             (ref ${$_[0]->[CN_WBUF]} eq 'ARRAY' ||
              ref ${$_[0]->[CN_WBUF]} eq 'Nginx::Engine::PP::Bufarray')) {

        $buffers = ${$_[0]->[CN_WBUF]};

    } else {
        die "Unknown write buffer type\n";
    }

    $_[0]->[CN_WOFF] = 0 unless defined $_[0]->[CN_WOFF];
    $_[0]->[CN_WIND] = 0 unless defined $_[0]->[CN_WIND];

    my $total  = 0;
    my $error  = 0;
    my $offset = $_[0]->[CN_WOFF];
    my $i      = 0;
    my $again  = 0;

    for ($i = $_[0]->[CN_WIND]; $i <= $#{$buffers}; $i++) {
        my $buf = $buffers->[$i];

        while ($offset < length($$buf)) {
            my $len = syswrite($fh, $$buf, length($$buf), $offset);

            if (!defined $len) {
                if ($!{EAGAIN} || $!{EWOULDBLOCK}) {
                    $again = 1;
                    last;
                } elsif ($!{EINTR}) {
                    next;
                } else {
                    $error = 1;
                    last;
                }
            } 

            $total  += $len;
            $offset += $len;

            if ($offset == length($$buf)) {
                $offset = 0;
                last;
            }
        }

        if ($again || $error) {
            last;
        }
    }

    $_[0]->[CN_WIND] = $i;
    $_[0]->[CN_WOFF] = $offset;

    my $wev = $_[0]->[CN_WRITE];

    if (!$error && $i <= $#{$buffers}) {
        $wev->[CEV_TIMEOUTAT] = time + $wev->[CEV_TIMEOUT];
        return;
    }

    if ($autoempty) {
        ${$_[0]->[CN_WBUF]} = '';
    }

    my $cb   = $wev->[CEV_CALLBACK];
    my $args = $wev->[CEV_ARGS];
    my $err  = $error; # protecting $error from modification

    $wev->[CEV_TIMEOUTAT] = time + $wev->[CEV_TIMEOUT];

    &$cb($c, $err, ${$c->[CN_RBUF]}, ${$c->[CN_WBUF]}, @$args);

    if ($_[0]->[CN_CLOSED]) {
        return;
    }

    if ($error) {
        ngxe_close($_[0]);
    } else {
        ngxe_writer_stop_reader_start($_[0]);
    }
}




sub _connect {
    my $c          = $_[0];
    my $fh         = $_[0]->[CN_FH];
    my $remoteaddr = $_[0]->[CN_REMOTEADDR];
    my $limit      = 3; 
    my $error      = 0;
    my $connected  = 0;

    while ($limit--) {
        my $rv = connect($fh, $remoteaddr);

        if (!$rv) {
            if ($!{EAGAIN} || $!{EWOULDBLOCK} || $!{EINPROGRESS}) {
                $error = 0;
                $connected = 0;
                last;
            } elsif ($!{EINTR}) {
                next;
            } elsif ($!{EISCONN}) {
                $error = 0;
                $connected = 1;
                last;
            } elsif ($!{ECONNRESET} || 
                     $!{ECONNREFUSED} || 
                     $!{EINVAL} ||
                     $!{ENETDOWN} || 
                     $!{ENETUNREACH} || 
                     $!{EHOSTDOWN} || 
                     $!{EHOSTUNREACH}) 
            {
                $error = 1;
                last;
            } else {
                $error = 1;
                next;
            }
        } else {
            last;
        }
    }

    if (!$error && !$connected) {
        return;
    }

    my $cb   = $c->[CN_WRITE]->[CEV_CALLBACK];
    my $args = $c->[CN_WRITE]->[CEV_ARGS];
    my $err  = $error; # protecting $error from modification

    # removing from select
    vec($win, $c->[CN_FILENO], 1) = 0;

    &$cb($c, $err, @$args);

    if ($_[0]->[CN_CLOSED]) {
        return;
    }

    if ($error) {
        ngxe_close($_[0]);
    }

}

sub ngxe_client ($$$$$;@) {
    # $localaddr, $remoteaddr, $remoteport, $timeout, $cb, ...

    my $fh = IO::Socket::INET->new(ReuseAddr => 1,
                                   LocalAddr => $_[0] eq '*' ? '' : $_[0],
                                   Blocking  => 0,
                                   Proto     => 'tcp') || return undef;
    my $fno = fileno($fh);

    my $c   = [];
    my $wev = [];

    $wev->[CEV_TIMEOUT]   = int(($_[3] + 500)/1000);
    $wev->[CEV_TIMEOUTAT] = time + $wev->[CEV_TIMEOUT];
    $wev->[CEV_TYPE]      = CEVT_CONNECT;
    $wev->[CEV_CALLBACK]  = $_[4];
    $wev->[CEV_ARGS]      = [@_[5..$#_]];

    $c->[CN_ID]         = $fno;
    $c->[CN_FH]         = $fh;
    $c->[CN_READ]       = undef;
    $c->[CN_WRITE]      = $wev;
    $c->[CN_REMOTEADDR] = scalar sockaddr_in($_[2], inet_aton($_[1]));

    $CONN{$fno}  = $c;
    $FDSET{$fno} = $c;

    vec($win,  $fno, 1) = 1;
    vec($wout, $fno, 1) = 1;

    _connect($c);

    return $c;
}








sub END {
    $NOPUSHBACK = 1;
}

1;
package Nginx::Engine::PP::Buf;

sub DESTROY {
    return if $NOPUSHBACK;

    my $self = shift;

    my $buf = \${$self};
    substr($$buf, 0, length($$buf), '');
    bless $buf, 'Nginx::Engine::PP::Buf';
    push @BUFSPOOL, $buf;

    $self = undef;

    $BUFSINUSE--;
    $BUFSFREE++;
}

1;
package Nginx::Engine::PP::Bufarray;

sub DESTROY {

    for (0 .. $#{$_[0]}) {
        next if !defined $_[0]->[$_] || ref $_[0]->[$_] ne 'SCALAR';
        ${$_[0]->[$_]} = '';

        push @BUFSPOOL, $_[0]->[$_];

        $_[0]->[$_] = undef;

        $BUFSINUSE--;
        $BUFSFREE++;
    }
}

1;
__END__

=head1 NAME

Nginx::Engine::PP - Pure-perl implementation of the Nginx::Engine

=head1 SYNOPSIS

    use Nginx::Engine::PP;

    ngxe_init "/path/to/ngxe-error.log", 256;

    # ...

    ngxe_loop;

=head1 DESCRIPTION

Pure-perl implementation af the Nginx::Engine. Might be useful
on Windows or if you want to do something that cannot be done correctly
using XS implementation, like fork()'ing another process for every
request. But this is not a bad thing, you should never use fork() or 
something that blocks for a long time in a high-performance event loop.
Use separate process instead.

=head1 SEE ALSO

L<Nginx::Engine>

=head1 AUTHOR

Alexandr Gomoliako <zzz@zzz.org.ua>

=head1 COPYRIGHT

Copyright 2011 Alexandr Gomoliako. All rights reserved.

=cut

