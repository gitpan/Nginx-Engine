#!/usr/bin/perl

use bytes;
use strict;
use warnings;
use Data::Dumper;

use JSON;
use HTTP::Parser::XS qw(parse_http_request);
use Tie::Judy;
use Nginx::Engine;
use Text::Soundex;
use Encode qw(decode_utf8);
use URI::Escape;
use Getopt::Std;

tie my %judy, 'Tie::Judy';
my %opts;

*my_soundex = \&soundex;

sub load_data {
    my $file = shift;

    open my $fh, '<', $file or die $!;
    if ($opts{s}) {
	while (my $line = <$fh>) {
	    next unless defined $line;
	    chomp $line;
	    my $key = my_soundex($line);
	    next unless $key;
	    
	    $judy{$key} = join(qq/\x00/, sort grep { $_ }
			       ($line, split /\x00/, $judy{$key} // ""));
	}
    }
    else {
	while (my $line = <$fh>) {
	    next unless defined $line;
	    chomp $line;
	    $judy{$line} = 0;
	}
    }
    close $fh;
    print "Loaded $file\n";
    print "Count: ", (0 + %judy), $/;
}

sub run_server {
    ngxe_init("", $opts{c});

    ngxe_server('*', $opts{p}, sub {
	ngxe_writer($_[0], 0, 1000, '', sub {
	    return if $_[1]; 
	    
	    ngxe_close($_[0]);
		    });
	
	ngxe_reader($_[0], NGXE_START, 5000, sub {
	    return if $_[1]; 

	    my $env = {}; 
	    my $len = parse_http_request($_[2], $env);

	    if ($len == -2 && length($_[2]) < 10000) {
		return;

	    } 
	    elsif ($len == -2 || $len == -1) {
		my $content = "Bad Request";
		$_[3] = "HTTP/1.0 400 Bad Request\x0d\x0a".
                    "Connection: close\x0d\x0a".
                    "Content-Length: ".length($content)."\x0d\x0a".
                    "Content-Type: text/html\x0d\x0a".
                    "\x0d\x0a".
                    $content;
		return;
	    }

	    # Generating web-page.
	    my $content = '';
	    my $status  = '200 OK';

	    if ($env->{'REQUEST_URI'} =~ m[/q/(.+)]o) {
		my $query = uri_unescape $1;
		
		if ($opts{s}) {
		    my $key = my_soundex($query);
		    my @results
			= (sort { $b =~ m[^$query]i <=> $a =~ m[^$query]i }
			   sort { length $a <=> length $b }
			   split /\x00/, $judy{$key});

		    if (scalar(@results) > $opts{m}) {
			@results = @results[0..$opts{m}-1];
		    }

		    $content = encode_json([ map { decode_utf8 $_ } 
					     @results ]);
		}
		else {
		    my @results = (tied %judy)->search(min_key => $query, 
						       limit => $opts{m});
		    $content = encode_json([ map { decode_utf8 $_ } 
					     grep /^$query/, @results ]);
		}
	    }
	    else {
		$content = "";
		$status = "404";
	    }

	    $_[3] = "HTTP/1.0 $status\x0d\x0a".
                "Connection: close\x0d\x0a".
                "Cache-Control: no-cache\x0d\x0a".
                "Pragma: no-cache\x0d\x0a".
                "Content-Type: text/html\x0d\x0a".
                "Content-Length: ".length($content)."\x0d\x0a".
                "\x0d\x0a".
                $content;
		    });
		});

    ngxe_loop;
}

sub main {
    getopts('sf:c:p:m:', \%opts);

    die "Please specify a dictionary file" unless $opts{f};

    $opts{c} //= 512;
    $opts{p} //= 55555;
    $opts{m} //= 100;

    load_data($opts{f});
    
    run_server;
}

main;

__END__

=pod

=head1 NAME

autocomplete-server.pl

=head1 USAGE

 % autocomplete-server.pl

   -f dictionary_file

   -c max_num_of_concurrent_connections (defaults to 512)

   -m max_num_of_results (defaults to 100)

   -p port (defaults to 55555)

   -s [Enable Soundex]

 #
 # plain string matching
 #
 % autocomplete-server.pl -f /usr/share/dict/words

 #
 # Soundex string matching
 #
 % autocomplete-server.pl -f /usr/share/dict/words -s

=head1 DESCRIPTION

B<autocomplete-server.pl> is a web server dedicated for serving
autocomplete strings. It is useful when you are creating an
autocompletion feature for your website. It uses L<Nginx::Engine> as
its backend and autocomplete strings are stored in Judy Array with the
implementation of Tie::Judy. So, it is supposed to be fast, scalable,
very easy-to-maintain, and it has a have small memory footprint. You
may try this tool with a word list as shown in the example above.

After the server is started, please query strings with the path
/q/YOUR_QUERY and an array-ref will be returned in JSON.

It supports two matching modes. The first is plain string matching,
and the second is Soundex matching (which uses L<Text::Soundex> as its
backend.)

=head1 AUTHOR

Yung-chung Lin L<henearkrxern@gmail.com>

=head1 COPYRIGHT

Copyright (C) 2011 Yung-chung Lin

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
