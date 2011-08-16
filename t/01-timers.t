
use strict;
use warnings;

use Test::More tests => 18;

my $ngxe_error_log = "ngxe_tests_error.log";

BEGIN { 
    use_ok('Nginx::Engine') 
};

END {
    unlink($ngxe_error_log) if -f $ngxe_error_log;
};

ngxe_init($ngxe_error_log, 64);

my $timer_ok = 0;
my $started = time;

ngxe_timeout_set(1000, sub { 
    $timer_ok = 1;  
    ok 1, "timer called back";
    ok $_[1] == 13, "arg0 passed to the first callback";
    ok $_[2] == 14, "arg1 passed to the first callback";
}, 13, 14);

ngxe_timeout_set(2000, sub {
    $timer_ok = 2;
    ok 1, "timer called back";
    ok $_[1] == 15, "arg0 passed to the second callback";
    ok $_[2] == 16, "arg1 passed to the second callback";
}, 15, 16);

my $interval_ok = 0;
ngxe_interval_set(1000, sub {
    ok 1, "interval called back";    
    ok $_[1] == 17, "arg0 passed to the third callback";
    ok $_[2] == 18, "arg1 passed to the third callback";

    $interval_ok++;

    if ($interval_ok == 3) {
        ngxe_interval_clear($_[0]);

        ok $timer_ok    == 2, "second timer after first";
        ok $interval_ok == 3, "interval called back $interval_ok times";

        diag "Spend time: ".(time - $started);

        exit;
    }
}, 17, 18);


ngxe_loop;
