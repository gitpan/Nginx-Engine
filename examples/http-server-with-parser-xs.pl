#!/usr/bin/perl

use bytes;
use strict;
use warnings;

use Nginx::Engine;
use HTTP::Parser::XS qw(parse_http_request);

# Parsing http request with another XS call.
# This XS call slows things down a bit but produces CGI-like %ENV.

ngxe_init("", 512);

ngxe_server('*', 55555, sub {

    # $_[0] - connection
    # $_[1] - remote address

    ngxe_writer($_[0], 0, 1000, '', sub {

        # $_[1] is set on error and is a very useful way to do
        # cleanup in event-driven applications.

        return if $_[1]; 


        # This event occurs if there is no more data
        # in the write buffer $_[3]. 

        # You have to do either one of the following here:
        # - close the connection;
        # - fill write buffer with something and return (restarts the writer);
        # - return (automatically stops writer and starts the reader);
        # - stop the writer and do something else (fetch some data
        #    from remote machine and then send it to the client
        #    for example)

        ngxe_close($_[0]);
    });

    ngxe_reader($_[0], NGXE_START, 5000, sub {

        # $_[1] is set on error and is a very useful way to do
        # cleanup in event-driven applications.

        return if $_[1]; 


        my $env = {}; 
        my $len = parse_http_request($_[2], $env);

        if ($len == -2 && length($_[2]) < 10000) {

            # Request incomplete and  is less than 10000 bytes.
            # This can fit our single buffer without growing it.

            # In 0.04 initially read buffer is about 16k and will 
            # grow once you fill up with 12k of data. 

            return;

        } elsif ($len == -2 || $len == -1) {

            # Larger than 10000 bytes and still incomplete
            # or incorrect.

            my $content = "Bad Request";
            $_[3] = "HTTP/1.0 400 Bad Request\x0d\x0a".
                    "Connection: close\x0d\x0a".
                    "Content-Length: ".length($content)."\x0d\x0a".
                    "Content-Type: text/html\x0d\x0a".
                    "\x0d\x0a".
                    $content;
            return;
        }


        # Reading small POST content.
        # This is just an example showing how to work with the
        # $_[4] (minlen) scalar.

        if ($env->{'REQUEST_METHOD'} eq 'POST') {

            if (!exists $env->{'CONTENT_LENGTH'} || 
                $env->{'CONTENT_LENGTH'} !~ /^\d+$/) 
            {
                # Note that CONTENT_LENGTH might not contain 
                # a number. XS parser does nothing about it and 
                # makes it insecure to use without additional checks.

                my $content = "Request Entity Too Large";
                $_[3] = "HTTP/1.0 413 Request Entity Too Large\x0d\x0a".
                        "Connection: close\x0d\x0a".
                        "Content-Length: ".length($content)."\x0d\x0a".
                        "Content-Type: text/html\x0d\x0a".
                        "\x0d\x0a".
                        $content;
                return;

            } elsif ($env->{'CONTENT_LENGTH'} + $len > 30000) {

                # If entire request is going to be larger
                # than 30000 we are not going to receive it.
                # Helps to avoid resource starvation in this 
                # case. You should write large requests to disk
                # or do something with them but don't keep them
                # in memory.

                my $content = "Request Entity Too Large";
                $_[3] = "HTTP/1.0 413 Request Entity Too Large\x0d\x0a".
                        "Connection: close\x0d\x0a".
                        "Content-Length: ".length($content)."\x0d\x0a".
                        "Content-Type: text/html\x0d\x0a".
                        "\x0d\x0a".
                        $content;
                return;

            } elsif ($env->{'CONTENT_LENGTH'} + $len > length($_[2])) {

                # If length of the request is larger that the 
                # data we have in the read buffer - setting minlen and 
                # returning. Reader will call us back again.

                # warn "waiting for more data to process\n";

                $_[4] = $env->{'CONTENT_LENGTH'} + $len;
                return; 
            }
        }



        # This is an example on how to do something asynchronously
        # and work with the connection later.

        if ($env->{'REQUEST_URI'} eq '/sleep') {

            ngxe_reader_stop($_[0]); 
            
            ngxe_timeout_set(5000, sub {
                my ($c, $buf) = @_[1,2];

                my $content = "sleep finished\x0d\x0a";
                $$buf = "HTTP/1.0 200 OK\x0d\x0a".
                        "Connection: close\x0d\x0a".
                        "Cache-Control: no-cache\x0d\x0a".
                        "Pragma: no-cache\x0d\x0a".
                        "Content-Type: text/html\x0d\x0a".
                        "Content-Length: ".length($content)."\x0d\x0a".
                        "\x0d\x0a".
                        $content;

                ngxe_writer_start($c);

            }, $_[0], \$_[3]); # connection, write buffer

            return;
        }



        # Generating web-page.

        my $content = '';
        my $status  = '200 OK';

        if ($env->{'REQUEST_URI'} eq '/') {
            $content = 'Ok <a href="/form/">/form/</a>';
        } elsif ($env->{'REQUEST_URI'} eq '/form/') {
            my $data = 'x' x 1460;  # data here is just to force packet
                                    # fragmenttion 

            $content = << "            END";
            <form method="POST" action="/post">
            <input type="text" name="text" value="your text here" /> 
            <input type="hidden" name="data" value="$data" /> 
            <input type="submit" name="post" value="post" /> 
            </form>
            END
        } elsif ($env->{'REQUEST_URI'} eq '/post') {
            $content = "<xmp>".$_[2]."</xmp>";
        } else {
            $content = "Not Found";
            $status = "404 Not Found";
        }

        $_[3] = "HTTP/1.0 $status\x0d\x0a".
                "Connection: close\x0d\x0a".
                "Cache-Control: no-cache\x0d\x0a".
                "Pragma: no-cache\x0d\x0a".
                "Content-Type: text/html\x0d\x0a".
                "Content-Length: ".length($content)."\x0d\x0a".
                "\x0d\x0a".
                $content;

        # After we set $_[3] and returned from the reader 
        # it'll automatically stops itself and start the the 
        # writer.

    });
});

ngxe_loop;
