package Catepod::Gameserver::CounterStrikeSource;

use strict;
use warnings;
use POE;

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
   print Dumper \@_;
      POE::Session->create(
        inline_states {
            _start            => \&start,               # received when the session starts
            _stop             => \&stop,                # received when the session is GC'ed
            _install          => \&install,             # internal signal to set the gameserver up the first time
            _remove           => \&remove,              # internal signal to remove the gameserver from disc
            _stop_gameserver  => \&stop_gameserver,     # internal signal to stop the gameserver
            _start_gameserver => \&start_gameserver,    # internal signal to start the gameserver
            shutdown          => \&shudown,             # the signal to use when you want this thing to shut down
            restart           => \&restart,             # signal sent when the gameserver should be restarted
        },
      );

}

sub start {

# workflow of this sub:
# determining whether the gameserver already exists on disc or not
# see whether we got the parameter to install it
# if we did, but its already there, error. if we didn't, and its not there, error
# install and/or start it.

}

sub start_gameserver {
# workflow of this sub:
# the gameserver is installed and ready to be started, fire it up with given parameters.

}

sub stop_gameserver {
# we want this gameserver to be stopped.
# error if the gameserver is not running
}

sub stop {
# this function doesn't do anything for now (it will log shit later on)
}

sub restart {
# restart the running gameserver. error if no gameserver is running.
}

sub install {
# the gameserver is not installed, install it, then call start_gameserver
}

sub remove {
# the gameserver was stopped, and now we can safely uninstall it.

}

sub shutdown {
# check whether we are supposed to uninstall the gameserver as well
# call _stop_gameserver, then remove if appropriate.
# remove wheels so that the session can be GC'ed
}

1;
