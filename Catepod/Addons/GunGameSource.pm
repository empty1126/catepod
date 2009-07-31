package Catepod::Addons::GunGameSource;

use strict;
use warnings;
use POE;
use Carp;
use File::Copy;
use File::Path;
use Archive::Tar;

my $logger = $main::logger;

#
# Workflow
#
#

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

    if ($install) {
        $logger->info( "Install " . __PACKAGE__ . " to gameserver in $path" );
        POE::Kernel->yield("_install");
    }
    else {
        $logger->info( "Deinstall " . __PACKAGE__ . " from gameserver in $path" );
        POE::Kernel->yield("_remove");
    }
}

sub stop {

    # this function doesn't do anything for now (it will log shit later on)
    $logger->info( __PACKAGE__ . " stopping." );
}

sub install {
    my $heap        = $_[HEAP];
    my $path        = $heap->{path};
    my $PACKAGE_DIR = $heap->{package_dir};
    my $mod         = $heap->{mod};

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

    $logger->info("Installation did complete sucessfull");

}

sub remove {
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

    if ( !rmtree("$path/cstrike/addons/metamod") ) {
        $logger->warn("Couldn't delete tree '$path/cstrike/addons/metamod': $!");
        return;
    }

    $logger->info("Deinstallation did complete sucessfull.");

}

1;
