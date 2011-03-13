package Nginx::Engine::Const;

use strict;
use warnings;

use constant {
    NGXE_START  => 0x01,
};

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(
    NGXE_START
);

1;
