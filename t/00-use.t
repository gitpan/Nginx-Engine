
use Test::More tests => 1;

BEGIN { 
    use_ok('Nginx::Engine') 
};


if (defined $Nginx::Engine::PP::VERSION) {
    diag "\n".
         " ************************************ \n".
         "\n".
         "    Using pure-perl implementation \n".
         "            version $Nginx::Engine::PP::VERSION \n".
         "\n".
         " ************************************ \n".
         "";
}
