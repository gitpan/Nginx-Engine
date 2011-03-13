package Nginx::Engine::Bufs;

use strict;
use warnings;
use bytes;

# use Digest::MD5;


# sub ngxe_bufs (;$) {
#     my $bufs = [];
#     push @$bufs, Nginx::Engine::ngxe_buf($_[0]) if defined $_[0];
#     bless $bufs, 'Nginx::Engine::Bufs';
# }
# 
# sub ngxe_bufsfile ($) {
#     open(FILE, $_[0]) || return undef;
# 
#     my $bufs = ngxe_bufs;
#     
#     while (1) {
#         my $buf = Nginx::Engine::ngxe_buf; push @$bufs, $buf;
#         my $len = sysread(FILE, $$buf, $NGXK_BUFSIZE);
#         if (!defined $len) {
#             close(FILE);
#             return undef;
#         } elsif ($len == 0) {
#             last;
#         }
#     }
#     close(FILE);
#     return $bufs;
# }
# 
# sub ngxe_bufslen ($) {
#     my $len = 0;
#     map { $len += length(${$_}) } @{$_[0]};
#     return $len;
# }
# 
# sub ngxe_bufsmd5 ($) {
#     my $md5 = new Digest::MD5;
#     foreach (@{$_[0]}) {
#         Digest::MD5::add($md5, ${$_});
#     }
#     return Digest::MD5::digest($md5);
# }
# 
# 
# sub ngxe_bufsfree ($) {
#     while (@{$_[0]}) {
#         Nginx::Engine::ngxe_buffree(pop(@{$_[0]}));
#     }
# }

sub DESTROY {
    while (@{$_[0]}) {
        Nginx::Engine::ngxe_buffree(pop(@{$_[0]}));
    }
}

1;
