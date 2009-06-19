package Catepod::Gameserver::CounterStrikeSource;

use strict;
use warnings;
use POE;
use POE::Wheel::Run;
use Carp;
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
    my $class = shift;    # not interesting
    use Data::Dumper;
    if ( @_ & 1 ) {
        carp( __PACKAGE__ . '->new needs even number of options' );
    }
    my %options = @_;
    my $install;
    my $path;
    my $params;
    if ( exists $options{'params'} ) {    # params passed directly to the GS
        $params = $options{'params'};
        delete $options{'params'};
    }
    else {
        croak( __PACKAGE__ . '->new needs a \'params\' argument.' );
    }
    if ( exists $options{'install'} ) {    # install shit or shit? shit.
        $install = $options{'install'};
        delete $options{'install'};
    }
    else {
        $install = 0;
    }
    if ( exists $options{'path'} ) {       #
        $path = $options{'path'};
        delete $options{'path'};
    }
    else {
        croak( __PACKAGE__ . '->new needs a \'path\' option.' );
    }

    if ( keys %options > 0 ) {
        carp(   __PACKAGE__
              . ': Unrecognized options in new(): '
              . join( ', ', keys %options ) );
    }
    POE::Session->create(
        inline_states => {
            _start   => \&start,    # received when the session starts
            _stop    => \&stop,     # received when the session is GC'ed
            _install => \&install
            ,    # internal signal to set the gameserver up the first time
            _remove =>
              \&remove,    # internal signal to remove the gameserver from disc
            _stop_gameserver =>
              \&stop_gameserver,    # internal signal to stop the gameserver
            _start_gameserver =>
              \&start_gameserver,    # internal signal to start the gameserver
            shutdown => \&shudown
            ,    # the signal to use when you want this thing to shut down
            restart =>
              \&restart,   # signal sent when the gameserver should be restarted
                           # signals for the Wheel
            got_child_stdout => \&child_stdout,
            got_child_stderr => \&child_stderr,
            got_child_close  => \&child_close,

        },
        heap => {
            install => $install,
            path    => $path,
            params  => $params,
        }
    );

}

sub start {
    my $heap    = $_[HEAP];
    my $install = $heap->{install};
    my $path    = $heap->{path};
    my $params  = $heap->{params};

#$logger->info(qq{starting gameserver: install: $install, path:$path, params:$params});
    if ( -e "$path/srcds_run" && $install ) {
        $logger->warn(
"You told me to install a gameserver, but it seems there is already one installed!"
        );
    }
    elsif ( ( !-e "$path/srcds_run" ) && !$install ) {
        $logger->warn(
"There is no gameserver in $path, and you told me not to install one, aborting."
        );
    }

    # install or start it, for now we only implement starting.
    if ($install) {
        $logger->warn("Installing is not implemented yet.");
    }
    else {
        POE::Kernel->yield('_start_gameserver');
    }
}

sub start_gameserver {

# workflow of this sub:
# the gameserver is installed and ready to be started, fire it up with given parameters.
    my $heap    = $_[HEAP];
    my $install = $heap->{install};
    my $path    = $heap->{path};
    my $params  = $heap->{params};

    chdir($path);
    $logger->debug( "params: " . join(" ", @$params));
    my $child = POE::Wheel::Run->new(
        Program     => "./test",
        StdoutEvent => "got_child_stdout",
        StderrEvent => "got_child_stderr",
        CloseEvent  => "got_child_close",
    ) or $logger->warn("Error: $!");
    $_[HEAP]->{wheel} = $child;
}

sub child_stdout {
    my $text = $_[ARG0];
    $logger->info( __PACKAGE__ . " OUTPUT: $text" );
}

sub child_stderr {
    my $text = $_[ARG0];
    $logger->warn( __PACKAGE__ . " ERROR: $text" );
}

sub child_close {
    delete $_[HEAP]->{wheel};
    $logger->warn( __PACKAGE__ . " gameserver exited." );
}

sub stop_gameserver {

    # we want this gameserver to be stopped.
    # error if the gameserver is not running
    $logger->warn("stop_gameserver not implemented yet");
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

    # the gameserver is not installed, install it, then call start_gameserver
    $logger->warn("install not implemented yet");
}

sub remove {

    # the gameserver was stopped, and now we can safely uninstall it.
    $logger->warn("remove not implemented yet");

}

sub shutdown {

    # check whether we are supposed to uninstall the gameserver as well
    # call _stop_gameserver, then remove if appropriate.
    # remove wheels so that the session can be GC'ed
}

1;
