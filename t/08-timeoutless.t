
use strict;
use warnings;

# use Test::More tests => ;
use Test::More 'no_plan';
use Digest::MD5 qw(md5);

my $ngxe_error_log = "ngxe_tests_error.log";

BEGIN { 
    use_ok('Nginx::Engine') 
};

END {
    unlink($ngxe_error_log) if -f $ngxe_error_log;
};


ngxe_init($ngxe_error_log, 64);

my $port = 51901;
my $port_max = 51999;
while ($port <= $port_max && !defined ngxe_server('*', $port, sub {

    ngxe_writer($_[0], 0, 1000, '', sub {
        if ($_[1]) {
            fail "expected exit";
            diag "server[writer]: error = $_[1]";
            exit;
        }
    });

    ngxe_reader($_[0], NGXE_START, 1000, sub {
        if ($_[1]) {
            fail "expected exit";
            diag "server[reader]: error = $_[1]";
            exit;
        }

        if ($_[2] =~ /\x0d\x0a/s) {
            $_[3] = "asdf\x0d\x0a";
            $_[2] = '';

            my $c = $_[0];

            ngxe_reader_stop($c);

            ngxe_timeout_set(2000, sub {
                ngxe_writer_start($c);
            });
        }
    });

})) { $port++; }

ngxe_client('127.0.0.1', '127.0.0.1', $port, 1000, sub { 

    if ($_[1]) {
        pass "client: cannot connect";
        exit;
    }

    my $t = time;

    ngxe_reader($_[0], 0, 0, sub {
        if ($_[1]) {
            fail "expected exit";
            diag "client[reader]: error = $_[1]";
            exit;
        }

        if ($_[2] =~ /\x0d\x0a/s) {
            ok time - $t > 1, "proper delay";
            ok $_[2] eq "asdf\x0d\x0a", "proper response";
            pass "expected exit";
            exit;
        }

    });

    ngxe_writer($_[0], NGXE_START, 1000, "go\x0d\x0a", sub {
        if ($_[1]) {
            fail "expected exit";
            diag "client[writer]: error = $_[1]";
            exit;
        }
    });

});

ngxe_timeout_set(10000, sub {
    fail "expected exit";
    diag "timed out after 10 seconds";
    exit;
});

ngxe_loop;

