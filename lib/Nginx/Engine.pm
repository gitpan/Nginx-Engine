package Nginx::Engine;

use strict;
use warnings;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(

    ngxe_init
    ngxe_bufsize
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

    NGXE_START
    NXSTART
);

our $VERSION = '0.08';

unless ($ENV{'NGXE_PP'}) {
    eval {
        require XSLoader;
        XSLoader::load('Nginx::Engine', $VERSION);
    };
    if ($@) {
        warn "Cannot load xs implementation: $@\n" if $ENV{'NGXE_VERBOSE'};
        require Nginx::Engine::PP;
        import Nginx::Engine::PP;
    }

} else {
    require Nginx::Engine::PP;
    import Nginx::Engine::PP;
}

if (!defined &Nginx::Engine::NXSTART) {
    eval qq(use Nginx::Engine::Const);
}

# Preloaded methods go here.

1;
__END__

=head1 NAME

Nginx::Engine - Asynchronous framework based on nginx

=head1 SYNOPSIS

    use Nginx::Engine;

    # Creating event loop with 4096 connetions
    # and ngxe-error.log as error log.
    ngxe_init("./ngxe-error.log", 4096);

    # Server that accepts new connection, 
    # sends "hi" and closes it.
    ngxe_server('*', 55555, sub {
        ngxe_writer($_[0], 1, 1000, "hi", sub {
            # $_[1] is error and return on error is always required
            # and it's there so you can do some cleanup if you need to.
            return if $_[1];

            ngxe_close($_[0]);
        });
    });

    # Server that reads whatever comes first
    # sends it back and closes connection.  
    # 
    ngxe_server('*', 55555, sub {
        ngxe_writer)$_[0], 0, 5000, '', sub {
            return if $_[1];

            ngxe_close($_[0]);
        });

        ngxe_reader($_[0], NGXE_START, 5000, sub {
            return if $_[1];

            $_[3] = $_[2]; # write_buffer = read_buffer 
            #_[2] = '';    # read_buffer = ''
            
            # writer starts automatically if there is 
            # data in the write buffer after this sub
            # returns
        });
    });

    # Connecting to 127.0.0.1:80 and disconnecting.
    ngxe_client('*', '127.0.0.1', 80, 2000, sub {
        if ($_[1]) {
            warn "$_[1]\n";
            return;
        }

        print "Connected, closing\n";
        ngxe_close($_[0]);
    });

    # Saying "N. Hello, World!" every second
    ngxe_interval_set(1000, sub { 
        print "$_[2]. Hello, $_[1]!\n"; 
        $_[2]++ 
    }, "World", 1);

    # Saying "Hello World!" once after 5000 ms.
    ngxe_timeout_set(5000, sub { 
        print "Hello, $_[1]!"; 
    }, "World");


    # Server that echoes everyhing back to the client.
    ngxe_server('*', 55555, sub {

        ngxe_writer($_[0], 0, 5000, '', sub {
            return if $_[1];

            # write buffer sent and cleared for us 

            # writer stops automatically if there is
            # no data in the write buffer after this sub
            # returns
        });

        ngxe_reader($_[0], NGXE_START, 5000, sub {
            return if $_[1];

            $_[3] = $_[2]; # copying read buffer to the write buffer
            $_[2] = '';    # clearing read buffer

            # writer starts automatically if there is 
            # data in the write buffer after this sub
            # returns
        });

    });

    ngxe_loop;


=head1 DESCRIPTION

Nginx::Engine is a simple high-performance asynchronous networking framework.
It's intended to bring nodejs-like performance and nginx's stability 
into Perl. It's almost as fast as nginx itself. And it can easily handle 
thousands or even tens of thousands of concurrent connections. Well, 
just like nginx. 

Internally it initializes nginx to access event loop, event modules and 
a lot of other core functions nginx provides. For every connection
Engine allocates a memory pool and destroys it whenever connection
is closed. Engine registers a cleanup function for stored perl arguments 
and callbacks to decrease their reference count with the destruction
of the memory pool. This way memory leaks are not possible even though 
two different memory allocators are used.

To achieve stability Nginx::Engine doesn't implement IO functions 
but rather simply reuses nginx's internal IO. This gives a huge 
performance boost as well by avoiding as much IO in perl as possible.

=head1 LIMITATIONS

fork() won't work properly in XS implementation. You should not use it 
after ngxe_init() at all.

Perl's signal handling won't work either after ngxe_init(). And there are
no signal handlers right now. 

=head1 DEPENDENCIES

No dependencies. Everything comes with the package.

=head1 SUPPORTED OPERATING SYSTEMS

Any unix or linux with working gcc, sh, perl and nginx should be ok.
It mostly depends on the ability to build nginx in a way that it can be 
linked as a shared library. If there is a problem you can
build nginx manually. Configure it without http module and with compiler 
option, that allows it to be linked as a shared library (not required for 
gcc on x86 and -fPIC for gcc on amd64). 

For other systems there is a pure-perl fallback based on C<select()>.

=head1 EXPORT

The following functions are exported by default:

    ngxe_init

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

    ngxe_close

    ngxe_loop

    NGXE_START

=head1 INITIALIZATION

Before you can do anything you have to initialize the engine by calling 
C<ngxe_init()> at the very beginning of your code. You cannot call any
other fuction before that. 

=head2 ngxe_init(ERROR_LOG[, CONNECTIONS])

Nginx requires error log to start. It is important to log error if some
system call fails or nginx runs out of some resource, like number of
connections or open files. You should always use log. But you can leave
it empty if you want to. 

Number of connections must be less than number of open files and sockets 
per process allowed by the system. You probably would need to tune your 
system anyway to use more then a couple of thousands. 

So, I suggest to start with something like this:

    ngxe_init("./ngxe-error.log", 4096);

=head1 TIMER

=head2 ngxe_timeout_set(TIMEOUT, CALLBACK, ...)

C<ngxe_timeout_set> creates new timer event to execute a callback
after I<TIMEOUT> ms. Takes any number of extra arguments after I<CALLBACK>
and stores them internally. I<CALLBACK> must be a CODE reference.

Returns timer identifier which can be used to remove event from the loop
with C<ngxe_timeout_clear>.

First argument passed to the callback is timer identifier and the rest are
all those extra arguments you set.

    $_[0] - timer
    @_[1..$#_] - extra args

For example, here is how to say "Hello, World" in 5 seconds, where "World" 
is an extra argument:

    ngxe_timeout_set(5000, sub { print "Hello, $_[1]!"; }, "World");

=head2 ngxe_timeout_clear(TIMER)

Prevents I<TIMER> event from happening, removes from the loop.

=head1 INTERVAL

=head2 ngxe_interval_set(TIMEOUT, CALLBACK, ...)

Ceates new timer event to execute a callback after I<TIMEOUT> ms. 
Resets timer every time until C<ngxe_interval_clear> is called.
Takes any number of extra arguments after I<CALLBACK> and stores them
internally. I<CALLBACK> must be a CODE reference.

Returns timer identifier which can be used to remove event from the loop
with C<ngxe_interval_clear>.

First argument passed to the callback is timer identifier and the rest are
all those extra arguments you set.

    $_[0] - timer
    @_[1..$#_] - extra args

For example, here is how to say "N. Hello, World" every second, 
where "World" and "N" are extra arguments:

    ngxe_interval_set(1000, sub { 
        print "$_[2]. Hello, $_[1]!\n"; 
        $_[2]++; 
    }, "World", 1);

=head2 ngxe_interval_clear(TIMER)

Stops interval identified as I<TIMER>, removes from the loop.

=head1 SERVER

=head2 ngxe_server(BIND_ADDRESS, BIND_PORT, CALLBACK, ...)

Creates new server connection, binds to the I<BIND_ADDRESS>:I<BIND_PORT>,
listens, accept new connections and executes I<CALLBACK> on them with 
extra arguments if any. Empty or '*' BIND_ADDRESS will result in using 
INADDR_ANY instead.

First and second arguments passed to the callback are connection identifier
and IP address of the remote host. All the rest - extra arguments you set.

    $_[0] - connection
    $_[1] - IP address connected
    @_[2..$#_] - extra args


For example, to accept new connection, print its address and close it
you need to create server and call C<ngxe_close> right inside the callback:

    ngxe_server('*', 55555, sub {
        print "$_[1] connected and discarded\n";
        ngxe_close($_[0]);
    });

=head1 CLIENT

=head2 ngxe_client(BIND_ADDR, REMOTE_ADDR, REMOTE_PORT, TIMEOUT, CALLBACK, ...)

Creates new client connection, binds to the I<BIND_ADDR>, connects
to the I<REMOTE_ADDR>:I<REMOTE_PORT>. And tries to do all of it in 
I<TIMEOUT> ms. Executes I<CALLBACK> after with any extra arguments.

Returns connection.

First argument passed to the callback is connection identifier, second - 
error variable and the rest are extra arguments.

    $_[0] - connection
    $_[1] - error indicator
    @_[2..$#_] - extra args

If error is set and TRUE than callback must return without any other 
ngxe_* functions beign called on this connection. 

Example, connecting to 127.0.0.1:80 and immediately closing connection:

    ngxe_client('127.0.0.1', '127.0.0.1', 80, 2000, sub {
        if ($_[1]) {
            warn "$_[1]\n";
            return;
        }

        print "Connected, closing\n";
        ngxe_close($_[0]);
    });

Notice, we are returning from callback on error. This is required behaviour.

=head1 READER AND WRITER

Reader is a way to receive data from connection asynchronously. 
It executes callback every time new data arrives. You should do 
whatever you need with the read buffer and clear it afterwards to 
avoid too much memory consumption. If you put some data into the
write buffer it will stop the reader and start the writer after.
You can call C<ngxe_reader_stop($_[0])> if you need to do 
something else before you can actually respond to the client.

Writer is a bit different and it will execute a callback only
when entire write buffer has been sent. Writer clears write 
buffer for you. You can modify it inside the callback and 
writer will send it again. You can achieve streaming this way.
Writer is automatically stops itself and starts the reader 
if write buffer is empty after the callback; You can call
C<ngxe_writer_stop($_[0])> if you need to deal with the 
connection later.

It doen't seem very clear and structured but speed is more
important here.

Read and write buffers can be used in both reader and writer.
You can save references to the read C<\$_[2]> or write 
buffer C<\$_[3]> if you want to access them later. Or you can
use C<ngxe_writer_buffer_set(CONNECTION, DATA)> to put something
into the write buffer if you have a connection already stored 
somewhere.

And both reader and writer can be recreated to achieve different 
processing schemes and if you can afford to slow things down.

=head2 ngxe_reader(CONN, FLAGS, TIMEOUT, CALLBACK, ...)

Creates a reader for connection identified as I<CONN>. Starts it
immediately if NGXE_START is given as a flag. If no data has been 
received in I<TIMEOUT> ms executes I<CALLBACK> with error identifier 
set to timeout. Extra args can be placed after I<CALLBACK>, as usual. 

If I<TIMEOUT> is set to 0 it is not going to be used at all.

Returns undef on error.

First argument paseed to the callback is connection identifier. 
Second is error.variable. Third and 4th are read and write buffers.
And the fifth argument is an amount of data required for callback.
Usefule to read data with known length.

    $_[0] - connection
    $_[1] - error indicator
    $_[2] - read buffer
    $_[3] - write buffer
    $_[4] - min length
    @_[5..$#_] - extra args

If error is set you must return from the subroutine avoiding any
ngxe_* calls on current connection C<$_[0]>.

For example, let's create server, read a few bytes from new connection
and close it:

    ngxe_server('*', 55555, sub {
        ngxe_reader($_[0], NGXE_START, 1000, sub {
            if ($_[1]) {
                return;
            }

            print "got $_[2]\n";
            ngxe_close($_[0]);
        });
    });

=head2 ngxe_reader_start(CONN)

Starts reader for connection I<CONN>. 

=head2 ngxe_reader_stop(CONN)

Stops reader for connection I<CONN>.

=head2 ngxe_reader_stop_writer_start(CONN)

Stops reader and starts writer for connection I<CONN>. 
Saves unnecessary perl --> XSUB --> perl transition.

=head2 ngxe_reader_timeout(CONN[, TIMEOUT])

Returns current timeout for the reader and sets it to I<TIMEOUT> 
if specified.

=head2 ngxe_writer(CONN, FLAGS, TIMEOUT, DATA, CALLBACK, ...)

Creates a writer for connection identified as I<CONN>. Starts it
immediately if NGXE_START is given as a flag. If no data has been send 
in I<TIMEOUT> ms executes I<CALLBACK> with error flag set to timeout. 
Extra args can be placed after I<CALLBACK>, as usual. Puts I<DATA> into 
the write buffer.

If I<TIMEOUT> is set to 0 timeout is not going to be used at all. 

Returns undef on error.

First argument paseed to the callback is connection identifier. 
Second is error.variable. Third and 4th are read and write buffers.

    $_[0] - connection
    $_[1] - error indicator
    $_[2] - read buffer
    $_[3] - write buffer
    @_[4..$#_] - extra args

If error is set you must return from the subroutine avoiding any
ngxe_* calls on current connection C<$_[0]>.

For example, let's create server, send a few bytes to new connection
and close it:

    ngxe_server('*', 55555, sub {
        ngxe_writer($_[0], NGXE_START, 1000, "hi", sub {
            if ($_[1]) {
                return;
            }

            ngxe_close($_[0]);
        });
    });


=head2 ngxe_writer_start(CONN)

Starts writer for connection I<CONN>. 

=head2 ngxe_writer_stop(CONN)

Stops writer for connection I<CONN>

=head2 ngxe_writer_stop_reader_start(CONN)

Stops writer and starts reader for connection I<CONN>. 
Saves unnecessary perl --> XSUB --> perl transition.

=head2 ngxe_writer_timeout(CONN[, TIMEOUT])

Returns current timeout for the writer and sets it to I<TIMEOUT> 
if specified.

=head2 ngxe_writer_buffer_set(CONN, DATA)

Puts I<DATA>.into the write buffer of the connection I<CONN>
replacing old data. Calls C<ngxe_writer_start()> afterwards.

=head1 CLOSE

=head2 ngxe_close(CONN)

Destroys reader, writer, closes socket and removes connection
from the loop.

=head1 EXAMPLES

There are quite a few examples in the F<examples/> directory.

=head1 EXAMPLE: ECHO SERVER

A bit more complex example involving manipulation with the buffers.

    use Nginx::Engine;

    ngxe_init("", 64);

    ngxe_server("*", 55555, sub {

        ngxe_reader($_[0], 0, 5000, sub { 

            # $_[0] - connection
            # $_[1] - error indicator
            # $_[2] - read buffer
            # $_[3] - write buffer
            # $_[4] - min length
            # @_[5..$#_] -- args, but we didn't set any

            if ($_[1]) {
                return;
            }

            # copying read buffer to the write buffer
            $_[3] = $_[2];

            # clearing read buffer
            $_[2] = '';

            # calls ngxe_reader_stop_writer_start if write
            # buffers is not empty

        });

        ngxe_writer($_[0], 0, 1000, "", sub {

            # $_[0] - connection
            # $_[1] - error indicator
            # $_[2] - read buffer
            # $_[3] - write buffer
            # @_[4..$#_] -- args, but we didn't set any

            if ($_[1]) {
                return;
            }

            # calls ngxe_writer_stop_reader_start if there is no
            # more data in the buffer

        });

        ngxe_reader_start($_[0]);
    });

    ngxe_loop;

=head1 SEE ALSO

node.js L<http://nodejs.org/>, nginx L<http://nginx.org/>, 
L<POE>, L<AnyEvent>

=head1 AUTHOR

Alexandr Gomoliako <zzz@zzz.org.ua>

=head1 LICENSE

Copyright 2010 Alexandr Gomoliako. All rights reserved.

FreeBSD License. Take a look at F<LICENSE> and F<nginx/LICENSE> files.

=cut

