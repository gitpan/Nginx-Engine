
use strict;
use warnings;

# use Test::More tests => ;
use Test::More 'no_plan';

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
while ($port <= $port_max && !defined ngxe_server('127.0.0.1', $port, sub {

    pass "Server accepted the client";

    ok $_[2] == 22, "arg0 passed to the server's callback";
    ok $_[3] == 23, "arg1 passed to the server's callback";

    ngxe_writer($_[0], 0, 1000, '', sub {
        pass "writer called back";
        ok $_[4] == 32, "arg0 passed to the writer's callback";
        ok $_[5] == 33, "arg1 passed to the writer's callback";

        if ($_[1]) {
            fail "Sending data to the client without write error" or
                BAIL_OUT "ngxe_writer($_[0]): '$_[1]'";
            return;
        }

        ok length($_[3]) == 0, "Sending data to the client without write error";

        ngxe_close($_[0]);

    }, 32, 33);

    ngxe_reader($_[0], 1, 1000, sub {
        pass "reader called back";
        ok $_[5] == 30, "arg0 passed to the reader's callback";
        ok $_[6] == 31, "arg1 passed to the reader's callback";

        if ($_[1]) {
            fail "Receiving data from the client without errors" or
                BAIL_OUT "ngxe_reader($_[0]): '$_[1]'";
            return;
        }

        if ($_[2] =~ /\x0d\x0a/s) {
            local $/ = "\x0d\x0a"; 
            chomp($_[2]);

            ok $_[2] eq 'hi', "Receiving data from the client without errors";

            $_[3] = "hello\x0d\x0a";
        } 

    }, 30, 31);


}, 22, 23)) { 
    $port++;
}

ngxe_client('127.0.0.1', '127.0.0.1', $port, 1000, sub { 
    pass "client called back";
    ok $_[2] == 24, "arg0 passed to the client's callback";
    ok $_[3] == 25, "arg1 passed to the client's callback";

    if ($_[1]) {
        pass "Cannot connect";
        exit;
        return;
    }

    pass "Connected to server";

    ngxe_reader($_[0], 0, 5000, sub {
        pass "reader called back";
        ok $_[5] == 28, "arg0 passed to the reader's callback";
        ok $_[6] == 29, "arg1 passed to the reader's callback";

        if ($_[1]) {
            ok $_[2] eq 'hello', "Detecting closed connection by server" 
                or BAIL_OUT "buffer = '$_[2]'";
            exit;
            return;
        }

        if ($_[2] =~ /\x0d\x0a/s) {
            local $/ = "\x0d\x0a"; 
            chomp($_[2]);

            ok $_[2] eq 'hello', 
                        "Receiving response from the server without errors";
        } 

    }, 28, 29);

    ngxe_writer($_[0], NGXE_START, 1000, "hi\x0d\x0a", sub {
        pass "writer called back";
        ok $_[4] == 26, "arg0 passed to the writer's callback";
        ok $_[5] == 27, "arg1 passed to the writer's callback";

        if ($_[1]) {
            fail "Sending data to the server without errors" or
                BAIL_OUT "ngxe_writer($_[0]): '$_[1]'";
            return;
        }

        ok length($_[3]) == 0, "Sending data to the server without errors";

    }, 26, 27);

}, 24, 25);

# just in case
ngxe_timeout_set(5000, sub {
    fail "expected exit";
    exit;
});


ngxe_loop;

