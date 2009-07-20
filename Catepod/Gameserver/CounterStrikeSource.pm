package Catepod::Gameserver::CounterStrikeSource;

use strict;
use warnings;
use POE;
use POE::Wheel::Run;
use Carp;
use File::Copy;
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
    if ( exists $options{'path'} ) {       #
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
            _start            => \&start,               # received when the session starts
            _stop             => \&stop,                # received when the session is GC'ed
            _install          => \&install,            # internal signal to set the gameserver up the first time
            _remove           => \&remove,              # internal signal to remove the gameserver from disc
            _stop_gameserver  => \&stop_gameserver,     # internal signal to stop the gameserver
            _start_gameserver => \&start_gameserver,    # internal signal to start the gameserver
            stop_gameserver   => \&stop_gameserver,     # the signal to use when you want this thing to get stopped
            start_gameserver  => \&start_gameserver,    #the signal to use when you want this thing to get started
            sndstop           => \&sndstop,             #the signal to send the SIGKILL
            _shutdown         => \&shutdown,             # the signal to use when you want this thing to shut down
            restart           => \&restart,             # signal sent when the gameserver should be restarted
                                                        # signals for the Wheel
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

    if ( -e "$path/srcds_run" && $install ) {
        $logger->warn( "You told me to install a gameserver, but it seems there is already one installed!" );
    	return;
    }
    elsif ( ( !-e "$path/srcds_run" ) && !$install ) {
        $logger->warn( "There is no gameserver in $path, and you told me not to install one, aborting." );
	return;
    }

    if ($install) {
	$logger->info("Starting installation of Gameserver in '$path'");
	POE::Kernel->yield('_install');
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
        Program     => ["./srcds_run", @$params], 
        StdoutEvent => "got_child_stdout",
        StderrEvent => "got_child_stderr",
        CloseEvent  => "got_child_close",
    ) or $logger->warn("Error: $!");
    $_[HEAP]->{wheel} = $child;
    POE::Kernel->post('catepod', 'add_gameserver'  => $_[HEAP]->{path}, $_[HEAP]->{wheel}->PID());
}

sub child_stdout {
    my $text = $_[ARG0];
    $logger->info( __PACKAGE__ . " " . $_[HEAP]->{wheel}->PID() . " OUTPUT: $text" );
}

sub child_stderr {
    my $text = $_[ARG0];
    $logger->warn( __PACKAGE__ . " " . $_[HEAP]->{wheel}->PID() .  " ERROR: $text" );
}

sub child_close {
    $logger->warn( __PACKAGE__ . " " . $_[HEAP]->{wheel}->PID() .  " gameserver exited." );
    delete $_[HEAP]->{wheel};
}

sub stop_gameserver {
    my $heap = $_[HEAP];
    my $path = $heap->{path};
    my $port = $heap->{port};

    my $chkalias = 1;
    if ( $chkalias == 0 ) { #chk whether the gameserver is running...
        $logger->warn("There does not run a gameserver in '$path' with port '$port'");
    	return;
    }elsif ( !-e "$path/srcds_run" ) { #chk wheter the gameserver is installed
        $logger->warn("There isn't installed, a gameserver in '$path'");
    	return;
    }else {
            $_[HEAP]->{wheel}->kill(9);
            POE::Kernel->delay(sndstop => 4);
    
            if ( $@ ) { $logger->warn("There some error's while killing Gameserver in '$path'"); }
            else {
                $logger->info("Gameserver has stopped successfull.");
            }
            
    }
}

sub sndstop {
    $logger->info("Attempting to kill Gameserver " . $_[HEAP]->{wheel}->PID() . " with SIGKILL" );
    $_[HEAP]->{wheel}->kill(15);
}

sub stop {

    # this function doesn't do anything for now (it will log shit later on)
    $logger->info( __PACKAGE__ . " stopping." );
}

sub restart {

    # restart the running gameserver. error if no gameserver is running.
    $logger->warn("restart not implemented yet");
}

sub install {
    my $heap = $_[HEAP];
    my $path = $heap->{path};
    my $PACKAGE_DIR = $heap->{packages};
    my $port = $heap->{port};

	unless ( $port >= 1024 && $port <= 65535 ) {
	    $logger->info("We need a port to install the Gameserver");
	    return;
	}

	my $file = $PACKAGE_DIR . "/counter-strike-source.tar";

	if ( mkdir($path) eq 0 ) {
	    $logger->warn("Error while creating directory '$path': $!");
	    return;
	}

	if ( chdir($path) eq 0 ) {
	    $logger->warn("Error while chainging directory to '$path'");
	    return;
	}

	if ( copy($file, ".") eq 0 ) {
	    $logger->warn("Error while copying '$file' to '$path': $!");
	    return;
 	}
	
	my $tar = Archive::Tar->new;
	if ( $tar->read($path . "counter-strike-source.tar", 1) eq "false" ) {
	    $logger->warn("Error while reading tar archive: $path/counter-strike-source.tar: $!");
            return;
 	}
	$tar->extract();

	if ( unlink($path . "/counter-strike-source.tar") eq "false" ) {
	    $logger->warn("Error while deleting installation file: $!");
	}

	$logger->info("Installation finished successfull");
	POE::Kernel->yield('_start_gameserver');
}

sub remove {

    # the gameserver was stopped, and now we can safely uninstall it.
    $logger->warn("remove not implemented yet");

}

sub shutdown {
    POE::Kernel->alias_remove($_[HEAP]->{path});
    POE::Kernel->yield('_stop_gameserver');
    # check whether we are supposed to uninstall the gameserver as well
    # call _stop_gameserver, then remove if appropriate.
    # remove wheels so that the session can be GC'ed
}

1;
