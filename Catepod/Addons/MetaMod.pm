package Catepod::Addons::MetaMod;

use strict;
use warnings;
use POE;
use Carp;
use File::Copy;
use File::Path;
use Archive::Tar;

my $logger = $main::logger;

sub create {
    my $class = shift;
    use Data::Dumper;
    if ( @_ & 1 ) {
        carp( __PACKAGE__ . '->new needs even number of options' );
    }
    my %options = @_;
    my $install;
    my $path;
    my $mod;
    my $PACKAGE_DIR;

    if ( exists $options{'install'} ) {
        $install = $options{'install'};
        delete $options{'install'};
    }
    else {
        $install = 0;
    }

    if ( exists $options{'path'} ) {
        $path = $options{'path'};
        delete $options{'path'};
    }
    else {
        croak( __PACKAGE__ . '->new needs a \'path\' option.' );
    }

    $mod = $options{'mod'};
    delete $options{'mod'};

    if ( exists $options{'package_dir'} ) {
        $PACKAGE_DIR = $options{'package_dir'};
        delete $options{'package_dir'};
    }
    else {
        $logger->warn("Need a Addons directory !");
        return;
    }

    if ( !-e "$PACKAGE_DIR" ) {
        $logger->warn("Couldn't find Addons directory $PACKAGE_DIR");
        return;
    }

    if ( keys %options > 0 ) {
        carp( __PACKAGE__ . ': Unrecognized options in new(): ' . join( ', ', keys %options ) );
    }

    POE::Session->create(
        inline_states => {
            _start   => \&start,      # received when the session starts
            _stop    => \&stop,       # received when the session is GC'ed
            _install => \&install,    # internal signal to set the addon up the first time
            _remove  => \&remove,     # internal signal to remove the addon from disc
        },
        heap => {
            install     => $install,
            path        => $path,
            mod         => $mod,
            package_dir => $PACKAGE_DIR,
        }
    );

}

sub start {
    my $heap    = $_[HEAP];
    my $install = $heap->{install};
    my $path    = $heap->{path};
    my $mod     = $heap->{mod};

    if ($install eq "install" ) {
        $logger->info( "Install " . __PACKAGE__ . " to gameserver in $path" );
        POE::Kernel->yield("_install");
    }
    elsif ( $install eq "reinstall" ) {
        $logger->info ( "Reinstall " . __PACKAGE__ . " for gameserver in $path" );
        POE::Kernel->yield("_remove");
        POE::Kernel->yield("_install");
    }
    elsif ( $install eq "remove" ) {
        $logger->info( "Deinstall " . __PACKAGE__ . " from gameserver in $path" );
        POE::Kernel->yield("_remove");
    }
}

sub stop {

    # this function doesn't do anything for now (it will log shit later on)
    $logger->info( __PACKAGE__ . " stopping." );
}

sub install {

    #
    # Workflow:
    #  -Check whether the mod is already installed
    #  -Edit metamod file
    #  -inform logger if there're failures
    #

    my $heap        = $_[HEAP];
    my $path        = $heap->{path};
    my $PACKAGE_DIR = $heap->{package_dir};
    my $mod         = $heap->{mod};

    #mal noch checken, ob der mod bereits installiert wurde
    
    if ( -e "$path/cstrike/addons/metamod" ) {
        $logger->warn("It seems, that " . __PACKAGE__ . " has already been installed.");
        return;
    }

    if ( !chdir($path) ) {
        $logger->warn("Couldn't chdir to $path: $!");
        return;
    }

    if ( !copy( "$PACKAGE_DIR/$mod.tar", "cstrike/" ) ) {
        $logger->warn("Error while copying file '$mod.tar' to $path: $!");
        return;
    }

    chdir("cstrike/");

    my $tar = Archive::Tar->new();
    $tar->read("$mod.tar");

    if ( !$tar->extract() ) {
        $logger->warn("Coudln't extract $mod.tar in $path: $!");
        return;
    }

    if ( !unlink("$mod.tar") ) {
        $logger->warn("Couldn't delete tar-installation file '$mod.tar': $!");
    }

    my $file = "liblist.gam";

    open ( my $filehandle, '<', $file );
    my @slurp = <$filehandle>;
    close $filehandle;

    my @new_file = grep { $_ !~ m/.*gamedll_linux.*$/} @slurp;

    open( $filehandle, '>', $file );
    print {$filehandle} $_ foreach @new_file;
    print $filehandle 'gamedll_linux "addons/metamod/dlls/metamod_i386.so" ;MetaMoD added by catepod' . "\n";
    close $filehandle;
    $logger->info("Installation of " . __PACKAGE__ . " did complete successful");

}

sub remove {

    #
    # Workflow:
    #  -Check whether the mod has been installed
    #  -Edit the metamodfile
    #  -remove sourcefiles from disc
    #  -inform the logger if errors
    #

    my $heap = $_[HEAP];
    my $path = $heap->{path};
    my $mod  = $heap->{mod};

    if ( !-e "$path" ) {
        $logger->warn("There isn't installed a gameserver in $path");
        return;
    }

    if ( !chdir($path) ) {
        $logger->warn("Coudln't chdir to $path: $!");
        return;
    }

    if ( !-e "cstrike/addons/metamod/" ) {
        $logger->warn( __PACKAGE__ . " have not been installed, yet " );
        return;
    }

    my $file = "cstrike/liblist.gam";

    open ( my $filehandle, '<', $file );
    my @slurp = <$filehandle>;
    close $filehandle;

    my @new_file = grep { $_ !~ m/.*gamedll_linux.*$/} @slurp;
    
    open( $filehandle, '>', $file );
    print {$filehandle} $_ foreach @new_file;
    close $filehandle;

    my $tree = "$path/cstrike/addons/metamod/";
   
    if ( !rmtree($tree) ) {
        $logger->warn("Couldn't delete tree $tree: $!");
        return;
    }

    $logger->info("Deinstallation of " . __PACKAGE__ . " did complete successful.");

}

1;
