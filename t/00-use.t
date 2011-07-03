
use Test::More tests => 1;

BEGIN {
    $ENV{'NGXE_VERBOSE'} = 1; 
}

BEGIN { 
    use_ok('Nginx::Engine') 
}


if (defined $Nginx::Engine::PP::VERSION) {
    diag "\n".
         " ************************************ \n".
         "\n".
         "    Using pure-perl implementation \n".
         "            version $Nginx::Engine::PP::VERSION \n".
         "\n".
         " ************************************ \n".
         "";

    if (open(FILE, "nginx/objs/ngxe.log")) {
        my $buf;
        read(FILE, $buf, -s FILE);
        close(FILE);

        diag "\n\nFallback Log:\n\n$buf\n".
             " ************************************ \n" if $buf;
    }

    if (open(FILE, "nginx/objs/ngxe-nginx.log")) {
        my $buf;
        read(FILE, $buf, -s FILE);
        close(FILE);

        diag "\n\nBuild Log:\n\n$buf\n".
             " ************************************ \n" if $buf;
    }
}
