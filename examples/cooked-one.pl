#!/usr/bin/perl

use strict;
use warnings;

use Nginx::Engine;
use Nginx::Engine::Cookies::Resolver;

# Using ready-to-use TCP resolver. It is the only coocked thing in 0.04.

ngxe_init("", 256);


ngxk_resolve("google.com", sub {
    if ($_[1]) {
        print "$_[0]: error: $_[1]\n";
        return;
    }

    print "$_[0] = $_[2]->[0] (".join(", ", @{$_[2]}).")\n";
});

ngxk_resolve("gjkgkjgjkkjgkjgkjgkjgkjkjgjk.com", sub {
    if ($_[1]) {
        print "$_[0]: error: $_[1]\n";
        return;
    }

    print "$_[0] = $_[2]->[0]\n";
});


ngxe_loop;
