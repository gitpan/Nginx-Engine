use 5.008008;
use ExtUtils::MakeMaker;

my $nginx_dir = "nginx";
my @ALL_INCS = ();
my @ALL_DEPS = ();
my @ALL_OBJS = ();
my @ALL_SRCS = ();
my $ALL_LIBS = '';

if (!-d $nginx_dir || !-f "$nginx_dir/configure") {
    die "Cannot find nginx distribution in \"$nginx_dir\" directory: $!\n";
}

if (!-f "$nginx_dir/objs/Makefile") {
    system("( cd $nginx_dir && ./configure --without-http ".
                "--without-http-cache --with-cc-opt=\"-fPIC\" && make )");
}

if (open(FILE, "$nginx_dir/objs/Makefile")) {
    my $line = 0;
    my $have_all_incs = 0; 
    while (<FILE>) {
        $line++;
        chomp;
        if (!$have_all_incs && /^ALL_INCS\s*=\s*-I\s*([^ \\]+)\s*\\?$/) {
            my $path = $1;
            push @ALL_INCS, $path =~ /^\// ? $path : "$nginx_dir/$path";

            while (<FILE>) {
                chomp;
                if (/^\s*-I\s*([^ \\]+)\s*\\?$/) {
                    my $path = $1;
                    push @ALL_INCS, $path =~ /^\// ? $path : "$nginx_dir/$path";
                } else {
                    last;
                }
            }

            $have_all_incs = 1;
        }

        if (/^\w+_DEPS\s*=\s*([^ \\]+)\s*\\?$/) {
            my $path = $1;
#             push @ALL_DEPS, $path =~ /^\// ? $path : "$nginx_dir/$path";
            push @ALL_DEPS, $path;

            while (<FILE>) {
                chomp;
                if (/^\s*([^ \\]+)\s*\\?$/) {
                    my $path = $1;
#                     push @ALL_DEPS, $path =~ /^\// ? $path : "$nginx_dir/$path";
                    push @ALL_DEPS, $path;
                } else {
                    last;
                }
            }
        }

        if (/^objs\/nginx:\s*([^ \\]+)\s*\\?$/) {
            my $path = $1;
            push @ALL_OBJS, $path =~ /^\// ? $path : "$nginx_dir/$path";
            $path =~ s/^objs\/src/src/;
            $path =~ s/\.o$/\.c/;
            push @ALL_SRCS, $path =~ /^\// ? $path : "$nginx_dir/$path";

            while (<FILE>) {
                chomp;
                if (/^\s*([^ \\]+)\s*\\?$/) {
                    my $path = $1;
                    push @ALL_OBJS, $path =~ /^\// ? $path : "$nginx_dir/$path";
                    $path =~ s/^objs\/src/src/;
                    $path =~ s/\.o$/\.c/;
                    push @ALL_SRCS, $path =~ /^\// ? $path : "$nginx_dir/$path";
                } else {
                    last;
                }
            }
        }


        if (/^\s*\$\(LINK\)/) {
            while (<FILE>) {
                chomp;
                if (/^\s*-l\s*/) {
                    s/^\s+//g;
                    s/\s+\\?\s*$//g;
                    $ALL_LIBS .= "$_ ";
                    while (<FILE>) {
                        chomp;
                        s/^\s+//g;
                        s/\s+\\?\s*$//g;
                        last if $_ eq '';
                        $ALL_LIBS .= $_;
                    }
                    last;
                } else {
                    next;
                }
            }
        }
    }

    warn "Nginx is ok\n";

} else {
    die "Cannot open file $nginx_dir/objs/Makefile: $!\n";
}



my $nginx_incs = join(" ", map { "-I$_" } @ALL_INCS);
my $nginx_srcs = join(" ", @ALL_SRCS);
my $nginx_deps = join(" ", @ALL_DEPS);
my $nginx_libs = $ALL_LIBS;
my $nginx_objs = join(" ", @ALL_OBJS);

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Nginx::Engine',
    VERSION_FROM      => 'lib/Nginx/Engine.pm', # finds $VERSION
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Nginx/Engine.pm', # retrieve abstract from module
       AUTHOR         => 'Alexandr Gomoliako <zzz@zzz.org.ua>') : ()),
    LIBS              => [$nginx_libs], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I. '.$nginx_incs.'', # e.g., '-I. -I/usr/include/other'
	# Un-comment this if you add C files to link with later:
#    OBJECT            => '$(O_FILES)', # link all the C files too
#    H => \@ALL_DEPS,
#    OBJECT            => '$(O_FILES)'." $nginx_incs $nginx_srcs", # link all the C files too
    OBJECT            => '$(O_FILES)'." $nginx_objs", # link all the C files too
);



