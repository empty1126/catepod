package Catepod::GsLogger;

use DBI;
use Time::HiRes;


sub new {
    my $class = shift;
    my $name  = shift;
    my $self  = { name => $name };
    bless $self, $class;
    return $self;
}

sub warn {
    my $self    = shift;
    my $message = shift;
    my $gsID    = shift;

    my $dsn     = "DBI:mysql:database=gswi;host=localhost;port=3306";
    my $dbh     = DBI->connect( $dsn, 'root', 'k23771' );
    
    my $crtime  = Time::HiRes::time;
        
    my $sth     = $dbh->prepare(qq{INSERT INTO gswi_logs VALUES ("", "$gsID", "$message", "catepod", "$crtime")});
   
    $sth->execute;
    $sth->finish;
    
    $dbh->disconnect(); 
}

DESTROY {
    print "";
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
