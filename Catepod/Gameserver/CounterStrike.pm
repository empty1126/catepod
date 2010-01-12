package Catepod::Gameserver::CounterStrike;

use strict;
use warnings;
use POE;
use POE::Wheel::Run;
use Carp;
use File::NCopy;
use File::Path;
use Archive::Tar;
use Time::HiRes;

my $logger = $main::logger;
my $gslogger = $main::gslogger;

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
    my $gsID;

    if ( exists $options{'params'} ) {
        $params = $options{'params'};
        delete $options{'params'};
    }
    else {
        croak( __PACKAGE__ . '->new needs a \'params\' argument.' );
    }

    if ( exists $options{'gsID'} ) {
        $gsID   = $options{'gsID'};
        delete $options{'gsID'};
    }
    else {
        $logger->warn("You didnt give me the server ID, exiting...");
        return;
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
            gsID     => $gsID,
        }
    );

}

sub start {
    my $heap    = $_[HEAP];
    my $install = $heap->{install};
    my $path    = $heap->{path};
    my $params  = $heap->{params};
    my $gsID    = $heap->{gsID};

    if ( -e "$path/hlds_run"  ) {
        if ( $install != "remove" && $install != "reinstall" )  {
            $logger->warn("You told me to install a gameserver, but it seems there is already one installed!");
            $gslogger->warn("It seems that in $path is already installed a gameserver !", $gsID);
            $gslogger->setstatus("installerr", $gsID);
            return;
        }
    }
    
    if ( !-e "$path/hlds_run" ) {
        unless ( $install eq  "install" ) {
            unless ( $install eq "reinstall" ) {
                $logger->warn("There is no gameserver in $path, and you told me not to install one, aborting.");
                $gslogger->warn("You told me not to install a gameserver, and there is no gameserver, please reinstall it.", $gsID);
                $gslogger->setstatus("startfail", $gsID);
                return;
            }
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
        if ( defined $_[KERNEL]->alias_resolve($path) ) {
            $logger->warn("Gameserver is already running, please stop it before starting it.");
            $gslogger->warn("Gameserver runs already, please stop it before starting it.", $gsID);
            $gslogger->setstatus("startfail", $gsID);
            return;
        }

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
    my $gsID    = $heap->{gsID};

    if ( !chdir($path) ) {
        $logger->warn("Couldn't change directory to $path: $!");
        $gslogger->warn("Coudln't change directory to $path: $!", $gsID);
        $gslogger->setstatus("startfailed", $gsID);
        return;
    }

    my $child = POE::Wheel::Run->new(
        Program     => [ "./hlds_run", @$params ],
        StdoutEvent => "got_child_stdout",
        StderrEvent => "got_child_stderr",
        CloseEvent  => "got_child_close",
    );

    if ( !$child ) {  
        $logger->warn("Error while starting gameserver: $!");
        $gslogger->warn("Error while starting gameserver: $!", $gsID);
        $gslogger->setstatus("startfailed", $gsID);
    }

    $_[HEAP]->{wheel} = $child;
	
    $gslogger->warn("Gameserver started succesfully.", $gsID);
    $gslogger->setstatus("started", $gsID);

}

sub child_stdout {
    my $text = $_[ARG0];
    
    open my $filehandle, '>>', 'LOG_12_JAN_2010.log';
        print $filehandle $text . "\n";
    close $filehandle;
        
}

sub child_stderr {
    my $text = $_[ARG0];

    open my $filehandle, '>>', 'LOG_12_JAN_2010.log';
        print $filehandle $text . "\n";
    close $filehandle;
    

}

sub child_close {
    $logger->warn( __PACKAGE__ . " " . $_[HEAP]->{wheel}->PID() . " gameserver exited." );
    delete $_[HEAP]->{wheel};
}

sub reinstall {
    my $heap = $_[HEAP];
    my $path = $heap->{path};
    my $port = $heap->{port};
    my $gsID = $heap->{gsID};

    if ( !-e $path . "/hlds_run" ) {
        if ( !-e $path ) {
            $logger->info("There isn't installed a gameserver in $path, we are going to install it now");
            $gslogger->warn("There isn't installed a gameserver in $path, we are going to install it now");
        }
    }
    else {
        
        if ( !rmtree($path) ) {
            $logger->warn("Couldn't delete gameserver in $path: $!");
            $gslogger->warn("Couldn't delete gameserver in $path: $!");
            $gslogger->setstatus("deinstallfail", $gsID);
            return;            
        }     
        
        $logger->info("Deinstallation of gameserver in $path finished successful.");
        $gslogger->warn("The deinstallation of gameserver finished successfully.", $gsID);
        $gslogger->setstatus("deinstallcompleted", $gsID);
    }

    $logger->info("Beginn with installtion of gameserver in $path.");
    $gslogger->warn("Starting new installation of gameserver", $gsID);
    $gslogger->setstatus("startinstall", $gsID);
    POE::Kernel->delay("_install" => 5 );

}

sub stop_gameserver {
    my $heap = $_[HEAP];
    my $path = $heap->{path};
    my $port = $heap->{port};
    my $gsID = $_[ARG1];

    POE::Kernel->alias_remove ( $_[HEAP]->{path} );

    if ( !-e "$path/hlds_run" ) { 
        $logger->warn("There isn't installed, a gameserver in '$path'");
        $gslogger->warn("Coudln't find gameserver in $path, please reinstall it.", $gsID);
        $gslogger->setstatus("nogsstop", $gsID);
    }
    else {
        
        if ( $_[HEAP]->{wheel}->put("quit") ) {
            $logger->warn("Error while stopping gameserver: $!");
            $gslogger->warn("An error occured while stopping gameserver: $!", $gsID);
            $gslogger->setstatus("stopfail", $gsID);
            return;
        }

        if ( !$_[HEAP]->{wheel}->kill(9) ) {
            $logger->warn("Error while killing the gameserver: $!");
            $gslogger->warn("An error occured while stopping gameserver: $!", $gsID);
            $gslogger->setstatus("stopfail", $gsID);
            return;
        }
        


        $logger->info("Gameserver has stopped successful.");
        $gslogger->warn("Gameserver has stopped successful.", $gsID);
        $gslogger->setstatus("stopped", $gsID);
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
    my $gsID    = $_[ARG3];

    if ( $_[HEAP]{wheel}->put($command) ) {
        $logger->warn("Error while putting $command in wheel: $!");
        $gslogger->warn("Couldn't post command $command to gameserver: $!", $gsID);
        return;
    }

    $logger->warn("Put command sucessfull into wheel !");
    $gslogger->warn("Processed command '$command' successful.", $gsID);
}

sub restart {

    # Workflow
    # -stop the gameserver (error message if server does not run)
    # -start the server (error will come from _start_gameserver)
    # -if there aren't errors, informate the logger

    my $heap = $_[HEAP];
    my $path = $heap->{path};
    my $gsID = $heap->{gsID};

    POE::Kernel->yield('_stop_gameserver');
    POE::Kernel->yield('_start_gameserver');

    $logger->info("Gameserver in $path did restart succesful.");
    $gslogger->warn("Gameserver in $path has restarted successfully.", $gsID);
}

sub install {
    my $heap        = $_[HEAP];
    my $path        = $heap->{path};
    my $PACKAGE_DIR = $heap->{packages};
    my $port        = $heap->{port};
    my $gsID        = $heap->{gsID};

    unless ( $port >= 1024 && $port <= 65535 ) {
        $logger->info("We need a port to install the Gameserver");
        $gslogger->warn("Installation failed: No port has been given.", $gsID);
        $gslogger->setstatus("installfail", $gsID);
        return;
    }

    if ( -e "$path/hlds_run"  ) {
        $logger->warn("It seems, that there is already installed a gameserver in $path");
        $gslogger->warn("There is no gameserver in $path, please reinstall it.", $gsID);
        $gslogger->setstatus("installfail", $gsID);
        return;
    }

    my $folder = $PACKAGE_DIR . "/Gameserver/Counter-Strike/";

    if ( !-e $folder ) {
    	$logger->warn("The source directory $folder doesn'e exists.");
        $gslogger->warn("Couldn't find the source dir of gameserver files, please contact the administration.", $gsID);
        $gslogger->setstatus("installfail", $gsID);
	    return;    
    }

    if ( !mkdir($path) ) {
        $logger->warn("Error while creating directory '$path': $!");
        $gslogger->warn("Couldn't create directory: $!", $gsID);
        $gslogger->setstatus("installfail", $gsID);
        return;
    }

    if ( !chdir($folder) ) {
        $logger->warn("Error while chainging directory to '$folder': $!");
        $gslogger->warn("Error while chainging directory to '$folder': $!", $gsID);
        $gslogger->setstatus("installfail", $gsID);
        return;
    }

    my $file = File::NCopy->new(recursive => 1, preserve => 1);

    if ( !$file->copy(".", $path . "/" ) ) {
        $logger->warn("Error while copying '$folder' to '$path': $!");
        $gslogger->warn("Error while copying '$folder' to '$path': $!");
        $gslogger->setstatus("installfail", $gsID);
        return;
    }

    $gslogger->warn("Installation complete, starting the gameserver...", $gsID);
    $gslogger->setstatus("installed", $gsID);
    $logger->info("Installation finished successful");
    POE::Kernel->alias_set($path);
    POE::Kernel->yield('_start_gameserver');
}

sub remove {
    my $heap = $_[HEAP];
    my $path = $heap->{path};
    my $user = $heap->{user};
    my $port = $heap->{port};
    my $gsID = $heap->{gsID};

    if ( !-e $path . "/hlds_run" ) { 
        $logger->warn("There isn't installed a gameserver in $path, jump over to installation");
        $gslogger->warn("The gameserver hasn't been installed, jumping to installation.");
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
    my $gsID = $heap->{gsID};

    unless ($port) {
        $logger->warn("Dont have a server port. Exiting.");
        $gslogger->warn("No gameserver port !", $gsID);
        $gslogger->setstatus("deinstallfail", $gsID);
        return;
    }

    unless ($path) {
        $logger->warn("We can not remove a gameserver without the server part. Exiting.");
        $gslogger->warn("We can't remove a server until we have a server part.", $gsID);
        $gslogger->setstatus("deinstallfail", $gsID);
        return;
    }

    $logger->warn($path);
    return;
    if ( !rmtree($path) ) {
        $logger->warn("Couldn't delete directoy from gameserver in $path: $!");
        $gslogger->warn("Couldn't delete directoy from gameserver in $path: $!", $gsID);
        $gslogger->setstatus("deinstallfail", $gsID);
        return;
    }
    
    $gslogger->warn("Deinstallation finished successful.", $gsID);
    $gslogger->setstatus("deinstalled", $gsID);
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
