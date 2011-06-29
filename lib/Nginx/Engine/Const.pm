package Nginx::Engine::Const;

use strict;
use warnings;

use constant {
    NGXE_START  => 0x01,
    NXSTART     => 0x01,
};

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(
    NGXE_START
    NXSTART
);

1;
__END__

=head1 NAME

Nginx::Engine::Const - Nginx::Engine's constants for internal usage

=head1 SYNOPSIS

    use Nginx::Engine::Const;


=head1 DESCRIPTION

This module is for internal usage only. 

For now exports couple of constants: NGXE_START and NXSTART.

=head1 SEE ALSO

L<Nginx::Engine>

=head1 AUTHOR

Alexandr Gomoliako <zzz@zzz.org.ua>

=head1 COPYRIGHT

Copyright 2011 Alexandr Gomoliako. All rights reserved.

=cut

