package Catepod::Gameserver::CounterStrike;

use strict;
use warnings;
use POE;
use POE::Wheel::Run;
use Carp;
use File::NCopy;
use File::Path;
use Archive::Tar;

my $logger = $main::logger;

#
# Workflow
# A gameserver is started by starting this PoCo (calling ->create())
# A gameserver is stopped by shutting down this PoCo (signalling 'shutdown')
# A gameserver can be restarted by signalling 'restart'
# If you pass create() the parameter xyz, it will install the gameserver before running it
# If you attempt to start a gameserver that is not installed, you'll get back an error signal and the session will die.
# If you pass 'shutdown' the parameter xyz it will remove the gameserver after stopping it.
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
    my $params;
    my $port;
    my $PACKAGE_DIR;

    if ( exists $options{'params'} ) {
        $params = $options{'params'};
        delete $options{'params'};
    }
    else {
        croak( __PACKAGE__ . '->new needs a \'params\' argument.' );
    }
    if ( exists $options{'install'} ) {
        $install = $options{'install'};
        delete $options{'install'};
    }
    else {
        $install = 0;
    }

    if ( exists $options{'port'} ) {
        $port = $options{'port'};
        delete $options{'port'};
    }

    if ( exists $options{'packages'} ) {
        $PACKAGE_DIR = $options{'packages'};
        delete $options{'packages'};
    }
    else {
        $logger->warn("Dont have the package dir ! Exiting...");
        return;
    }
    if ( exists $options{'path'} ) {    #
        $path = $options{'path'};
        delete $options{'path'};
    }
    else {
        croak( __PACKAGE__ . '->new needs a \'path\' option.' );
    }

    if ( keys %options > 0 ) {
        carp( __PACKAGE__ . ': Unrecognized options in new(): ' . join( ', ', keys %options ) );
    }

    POE::Session->create(
        inline_states => {
            _start            => \&start,              # received when the session starts
            _stop             => \&stop,               # received when the session is GC'ed
            _install          => \&install,            # internal signal to set the gameserver up the first time
            _remove           => \&_remove,            # internal signal to remove the gameserver from disc
            remove            => \&remove,             # internal signal to check somethings before removing the server 
            _reinstall        => \&reinstall,          # internal signal to reinstall the gameserver
            _stop_gameserver  => \&stop_gameserver,    # internal signal to stop the gameserver
            _start_gameserver => \&start_gameserver,   # internal signal to start the gameserver
            _shutdown         => \&shutdown,           # the signal to use when you want this thing to shut down
            _process_command  => \&process_command,    # the signal to use when you want to send a command to the server
            stop_gameserver   => \&stop_gameserver,    # the signal to use when you want this thing to get stopped
            start_gameserver  => \&start_gameserver,   # the signal to use when you want this thing to get started
            
            #signals for the wheel
            got_child_stdout  => \&child_stdout,
            got_child_stderr  => \&child_stderr,
            got_child_close   => \&child_close,

        },
        heap => {
            install  => $install,
            path     => $path,
            params   => $params,
            packages => $PACKAGE_DIR,
            port     => $port,
        }
    );

}

sub start {
    my $heap    = $_[HEAP];
    my $install = $heap->{install};
    my $path    = $heap->{path};
    my $params  = $heap->{params};

    if ( -e "$path/hlds_run" && ( $install != "remove" || $install != "reinstall" ) ) {
        $logger->warn("You told me to install a gameserver, but it seems there is already one installed!");
        return;
    }
    
    if ( !-e "$path/hlds_run" ) {
        unless ( $install eq  "install" ) {
            $logger->warn("There is no gameserver in $path, and you told me not to install one, aborting.");
            return;
        }
    }

    if ($install eq "install" ) {
        $logger->info("Starting installation of Gameserver in '$path'");
        POE::Kernel->yield('_install');
    }
    elsif ( $install eq "reinstall" ) {
        POE::Kernel->yield('_reinstall');        
    }
    else { 
        POE::Kernel->alias_set($path);
        POE::Kernel->yield('_start_gameserver');
    }

}

sub start_gameserver {

    # workflow of this sub:
    # the gameserver is installed and ready to be started, fire it up with given parameters. - done
    # find function to check whether the server is already running

    my $heap    = $_[HEAP];
    my $install = $heap->{install};
    my $path    = $heap->{path};
    my $params  = $heap->{params};

    chdir($path);
    my $child = POE::Wheel::Run->new(
        Program     => [ "./hlds_run", @$params ],
        StdoutEvent => "got_child_stdout",
        StderrEvent => "got_child_stderr",
        CloseEvent  => "got_child_close",
    ) or $logger->warn("Error: $!");
    $_[HEAP]->{wheel} = $child;

}

sub child_stdout {
    my $text = $_[ARG0];
    $logger->info( __PACKAGE__ . " " . $_[HEAP]->{wheel}->PID() . " OUTPUT: $text" );
}

sub child_stderr {
    my $text = $_[ARG0];
    $logger->warn( __PACKAGE__ . " " . $_[HEAP]->{wheel}->PID() . " ERROR: $text" );
}

sub child_close {
    $logger->warn( __PACKAGE__ . " " . $_[HEAP]->{wheel}->PID() . " gameserver exited." );
    delete $_[HEAP]->{wheel};
}

sub reinstall {
    my $heap = $_[HEAP];
    my $path = $heap->{path};
    my $port = $heap->{port};

    if ( !-e $path . "/hlds_run" ) {
        $logger->info("There isn't installed a gameserver in $path, we are going to install it now");
    }
    else {

            
        if ( $_[HEAP]{wheel} ) {

            if ( $_[HEAP]->{wheel}->put("quit") ) {
                $logger->warn("Error while stopping gameserver: $!");
                return;
            }

            if ( !$_[HEAP]->{wheel}->kill(9) ) {
                $logger->warn("Error while killing the gameserver: $!");
                return;
            }

            if ( !rmtree($path) ) {
                $logger->warn("Couldn't delete gameserver in $path");
                return;            
            }

        }

        
        $logger->info("Deinstallation of gameserver in $path finished successful.");

    }

    $logger->info("Beginn with installtion of gameserver in $path.");
    POE::Kernel->delay("_install" => 5 );

}

sub stop_gameserver {
    my $heap = $_[HEAP];
    my $path = $heap->{path};
    my $port = $heap->{port};

    if ( !$_[HEAP]->{wheel} ) {
        $logger->warn("There does not run a gameserver in '$path' with port '$port'");
    }
    elsif ( !-e "$path/hlds_run" ) { 
        $logger->warn("There isn't installed, a gameserver in '$path'");
    }
    else {
        
        if ( $_[HEAP]->{wheel}->put("quit") ) {
            $logger->warn("Error while stopping gameserver: $!");
            return;
        }

        if ( !$_[HEAP]->{wheel}->kill(9) ) {
            $logger->warn("Error while killing the gameserver: $!");
            return;
        }

        $logger->info("Gameserver has stopped successful.");

    }
}


sub stop {

    # this function doesn't do anything for now (it will log shit later on)
    $logger->info( __PACKAGE__ . " stopping." );
}

sub process_command {

    # Workflow
    # send the commands from $_[ARG0] to the server

    my $command = $_[ARG1];

    if ( $_[HEAP]{wheel}->put($command) ) {
        $logger->warn("Error while putting $command in wheel: $!");
        return;
    }

    $logger->warn("Put command sucessfull into wheel !");

}

sub restart {

    # Workflow
    # -stop the gameserver (error message if server does not run)
    # -start the server (error will come from _start_gameserver)
    # -if there aren't errors, informate the logger

    my $heap = $_[HEAP];
    my $path = $heap->{path};

    POE::Kernel->yield('_stop_gameserver');
    POE::Kernel->yield('_start_gameserver');

    $logger->info("Gameserver in $path did restart succesful.");
}

sub install {
    my $heap        = $_[HEAP];
    my $path        = $heap->{path};
    my $PACKAGE_DIR = $heap->{packages};
    my $port        = $heap->{port};

    unless ( $port >= 1024 && $port <= 65535 ) {
        $logger->info("We need a port to install the Gameserver");
        return;
    }

    if ( -e "$path/hlds_run"  ) {
        $logger->warn("It seems, that there is already installed a gameserver in $path");
        return;
    }

    my $folder = $PACKAGE_DIR . "/Gameserver/Counter-Strike/";

    if ( !-e $folder ) {
    	$logger->warn(" The source directory $folder doesn'e exists.");
	return;    
    }

    if ( !mkdir($path) ) {
        $logger->warn(" Error while creating directory '$path': $!");
        return;
    }

    if ( !chdir($folder) ) {
        $logger->warn( " Error while chainging directory to '$folder'");
        return;
    }

    my $file = File::NCopy->new(recursive => 1, preserve => 1);

    if ( !$file->copy(".", $path . "/" ) ) {
        $logger->warn( " Error while copying '$folder' to '$path': $!");
        return;
    }

    $logger->info("Installation finished successful");
    POE::Kernel->alias_set($path);
    POE::Kernel->yield('_start_gameserver');
}

sub remove {
    my $heap = $_[HEAP];
    my $path = $heap->{path};
    my $user = $heap->{user};
    my $port = $heap->{port};

    if ( !-e $path . "/hlds_run" ) { 
        $logger->warn("There isn't installed a gameserver in $path, jump over to installation");   
    }
    else {

        if ( $_[HEAP]{wheel} ) {
            POE::Kernel->yield('_stop_gameserver');
        }

        POE::Kernel->yield('_remove');
    }
}

sub _remove {

    #workflow of this sub:
    #yield the signal to stop gameserver, after that
    #we can savely remove the gameserver, after that
    #informate a log-info-message

    my $heap = $_[HEAP];
    my $path = $heap->{path};
    my $port = $heap->{port};

    unless ($port) {
        $logger->warn("Dont have a server port. Exiting.");
        return;
    }

    unless ($path) {
        $logger->warn("We can not remove a gameserver without the server part. Exiting.");
        return;
    }

    if ( !rmtree($path) ) {
        $logger->warn("Couldn't delete directoy from gameserver in $path: $!");
        return;
    }

    $logger->info("Deinstallation finished succesfull in $path.");
}

sub shutdown {
    POE::Kernel->alias_remove( $_[HEAP]->{path} );
    POE::Kernel->yield('_stop_gameserver');

    # check whether we are supposed to uninstall the gameserver as well
    # call _stop_gameserver, then remove if appropriate.
    # remove wheels so that the session can be GC'ed
}

1;
