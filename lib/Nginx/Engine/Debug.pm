package Nginx::Engine::Debug;

use strict;
use warnings;

use POSIX;

our $VERSION = '0.02';

my $time = time;

BEGIN {
    $ENV{'NGXE_DEBUG'} ||= 0;
    $ENV{'NO_FILTER'}  ||= 0;

    if (exists $ARGV[0] && defined $ARGV[0]) {
        if ($ARGV[0] eq '--ngxe-debug') {
            $ENV{'NGXE_DEBUG'} = 1;
            shift @ARGV;
        }
    }

    eval {
        require Filter::Util::Call;
    }; 
    if ($@) {
        $ENV{'NO_FILTER'} = 1;
    } else {
        import Filter::Util::Call;
    }
}


sub timestamp { 
    if (time - $time > 0) {
        $time = time;
        print STDERR "\n".POSIX::strftime("timestamp: %Y-%m-%d %H:%M:%S", 
                                           localtime(time))."\n\n"; 
    }
}

sub import {
    return if $ENV{'NO_FILTER'};
    return unless $ENV{'NGXE_DEBUG'};

    $| = 1;

    filter_add(sub {
        my $status = filter_read();

        if (/^\s*#\s*DEBUG/g) {
            s/^\s*#\s*DEBUG\s*#?\s*/Nginx::Engine::Debug::timestamp;/g;
        } elsif ($ENV{'NGXE_DEBUG'} >= 1 && /^\s*#\s*warn/g) {
            s/^\s*#\s*/Nginx::Engine::Debug::timestamp;/g;
        }

        return $status;
    });
}


1;
__END__

=head1 NAME

Nginx::Engine::Debug - simple code filter for debugging purposes

=head1 SYNOPSIS

    use Nginx::Engine::Debug;

    # warn "this is going to show up with NGXE_DEBUG=1 only\n";


=head1 DESCRIPTION

This simple debug filter uncomments all the warnings on C<NGXE_DEBUG=1> 
environmental variable or C<--ngxe-debug> command line argument.
Therefore doesn't impact performance in a normal production mode.

=head1 SEE ALSO

L<Nginx::Engine>

=head1 AUTHOR

Alexandr Gomoliako <zzz@zzz.org.ua>

=head1 COPYRIGHT

Copyright 2011 Alexandr Gomoliako. All rights reserved.

=cut

