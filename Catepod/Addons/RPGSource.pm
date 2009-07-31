package Catepod::Addons::RPGSource;

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

    # we need to check whether the required addons are installed,
    # for here, we need the metamod plugin

    if ( !-e "$path/cstrike/addons/metamod/" ) {
        $logger->warn("Couldn't find required addon metamod, without it, " . __PACKAGE__ . " wont work");
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

    #the mod has been installed,
    #for now, we need to write a line into the metamod file

    open ( my $filehandle, '>>', "$path/cstrike/addons/metamod/metaplugins.ini");

    my $line = "addons/cssrpg/bin/cssrpg_mm ;CSS:RPG Plugin ;Added by Catepod";
    print $filehandle "$line\n";
    close $filehandle;

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

    my $file = "$path/cstrike/addons/metamod/metaplugins.ini";
    open ( my $filehandle, '<', $file  ) or $logger->info("Could not open $file: $!");

    my @slurp = <$filehandle>;
    close $filehandle;
    my @new_file;

    foreach my $current_line (@slurp) {
        if ( $current_line =~ /*RPG Plugin*/ ) { #found strings in metaplugins.ini and replace them
            push @new_file, $current_line;
        }   
    }

        my ( $first, $secound ) = split ( "@new_file", "@slurp" );
        my $newfile = "$first $secound";
        
        open ( $filehandle, '>', $file );
        print $filehandle $newfile;
        close $filehandle;

    if ( !rmtree("$path/dwadawdawcstrike/dwadwadawaddons/metamod") ) {
        $logger->warn("Couldn't delete tree '$path/cstrike/addons/metamod': $!");
        return;
    }

    $logger->info("Deinstallation did complete sucessfull.");

}

1;
