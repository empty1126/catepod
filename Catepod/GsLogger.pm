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

sub setstatus {
    my $self    = shift;
    my $status  = shift;
    my $gsID    = shift;

    if ( $status eq "" || $gsID eq "" ) { }
    else {

        my $dsn     = "DBI:mysql:database=gswi;host=localhost;port=3306";
        my $dbh     = DBI->connect( $dsn, 'xxxx', 'xxxx' );
    
        my $crtime  = Time::HiRes::time;
    
        my $sth     = $dbh->prepare(qq{UPDATE gswi_gameserver SET status="$status" WHERE gsID="$gsID"});
   
        $sth->execute;
        $sth->finish;
    
        $dbh->disconnect(); 
    }
}

DESTROY {
    print "";
}

1;
