package Catepod::Logger;
use Sys::Syslog;

sub new {
    my $class = shift;
    my $name  = shift;
    my $self  = { name => $name };
    openlog $name, undef, 'LOG_DAEMON';    # don't forget this
    bless $self, $class;
    return $self;
}

sub warn {
    my $self    = shift;
    my $message = shift;
    syslog( 'LOG_WARNING', "$$: " . $message );
}

sub error {
    my $self    = shift;
    my $message = shift;
    syslog( 'LOG_ERR', "$$: " . $message );
    syslog( 'LOG_ERR', "$$: Exiting.");
    die($message);
}

sub info {
    my $self    = shift;
    my $message = shift;
    syslog( 'LOG_INFO', "$$: " . $message );
}

sub debug {
    my $self    = shift;
    my $message = shift;
    syslog( 'LOG_DEBUG', "$$: " . $message );
}
DESTROY {
    closelog();
}

1;

#
#Levels
#
#    * LOG_EMERG - system is unusable
#    * LOG_ALERT - action must be taken immediately
#    * LOG_CRIT - critical conditions
#    * LOG_ERR - error conditions
#    * LOG_WARNING - warning conditions
#    * LOG_NOTICE - normal, but significant, condition
#    * LOG_INFO - informational message
#    * LOG_DEBUG - debug-level message
#
