
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

my $data1 = "x" x 100000;
my $large1     = \$data1;
my $large1_md5 = md5($data1);

my $port = 51901;
my $port_max = 51999;

while ($port <= $port_max && !defined ngxe_server('*', $port, sub {

    ngxe_writer($_[0], NGXE_START, 1000, $large1, sub {
        if ($_[1]) {
            fail "expected exit";
            diag "server[writer]: error = $_[1]";
            exit;
        }

        ngxe_close($_[0]);
    });

})) { $port++; }

ngxe_client('127.0.0.1', '127.0.0.1', $port, 1000, sub { 

    if ($_[1]) {
        pass "client: cannot connect";
        exit;
    }

    ngxe_reader($_[0], NGXE_START, 5000, sub {
        if ($_[1]) {
            ok $large1_md5 eq md5(@{$_[5]}), "expected response";
            pass "expected exit";
            exit;
        }

        push @{$_[5]}, "$_[2]";
        $_[2] = '';

    }, []);

});

ngxe_timeout_set(10000, sub {
    fail "expected exit";
    diag "timed out after 5 seconds";
    exit;
});

ngxe_loop;

