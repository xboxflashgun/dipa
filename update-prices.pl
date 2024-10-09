#!/usr/bin/perl -w

# fix for "Maximum header size exceeded"
$ENV{MOJO_MAX_LINE_SIZE} = 32768;

use Cpanel::JSON::XS;
use DBI;
use Mojo::UserAgent;
use Encode;
use Data::Dumper;
use Bytes::Random::Secure qw( random_bytes_base64 );
use utf8;

$|++;
# my $DEBUG = 1;
my $MINBATCH = 900;			# 1..900

# Correlation Vector: https://github.com/microsoft/CorrelationVector
my $mscv = random_bytes_base64(7, '');
$mscv =~ s/=//g;
$mscv =~ s/\+/3/g;
$mscv = "$mscv+F.1";

if(scalar(@ARGV) != 1)	{

	print "Usage: $0 [market]\nEx: $0 us\n\n";
	exit 0;

}

my $market = $ARGV[0];

my $dbh = DBI->connect("dbi:Pg:dbname=dipa") || die;
my $ua = Mojo::UserAgent->new;
$ua->inactivity_timeout(300);

# $coder = Cpanel::JSON::XS->new->allow_nonref;

# reading bc list
my %bc;
map { $bc{$_->[0]} = $_->[1] } $dbh->selectall_array("select legacyid,bingid from bc360list");

my @all = map { $_ -> [0] } $dbh->selectall_array("select bigid from products order by random()");
while( my @slice = splice(@all, 0, int($MINBATCH + rand(98))) ) {

	my $str = join ',', @slice;
	print " * Slice size: ", scalar(@slice)     if $DEBUG;
	get_prices($str);
	sleep 1;

}

$dbh->disconnect;


##########################################

sub get_prices {

	my $str = shift;

	my $json = $ua->get("https://displaycatalog.mp.microsoft.com/v7.0/products?".
		"bigIds=$str&market=$market&languages=en&MS-CV=$mscv")->result->json;

	$dbh->begin_work;

	foreach $pr (@{$json->{Products}}) {

		my $bigid = $pr->{'ProductId'};

		for $sku (@{$pr->{'DisplaySkuAvailabilities'}}) {

			my $skuid = $sku->{'Sku'}->{'SkuId'};
			my $skutype = $sku->{'Sku'}->{'SkuType'};

			for $av (@{$sku->{'Availabilities'}})   {

				my $plt;	# platform shoud be Windows.Xbox
				for $pl (@{$av->{'Conditions'}->{'ClientConditions'}->{'AllowedPlatforms'}})    {

					$plt = 1          if($pl->{'PlatformName'} eq 'Windows.Xbox');

				}
				next if not defined $plt;

				my $msrpp = $av->{'OrderManagementData'}->{'Price'}->{'MSRP'};
				my $listp = $av->{'OrderManagementData'}->{'Price'}->{'ListPrice'};

				if( grep { /Purchase/ } @{$av->{'Actions'}} )	{

					my $stdate  = $av->{Conditions}->{StartDate};
					my $enddate = $av->{Conditions}->{EndDate};
					my $remid = '';

					$remid = $av->{Remediations}->[0]->{BigId}	if( $av->{RemediationRequired} );

					$dbh->do('insert into prices(bigid,skuid,region,remid,stdate,enddate,msrp,listprice) values($1,$2,$3,$4,$5,$6,$7,$8)
						on conflict(bigid,skuid,region,remid,stdate) do update set enddate=$6,msrp=$7,listprice=$8', undef,
						$bigid, $skuid, $market, $remid, $stdate, $enddate, $msrpp, $listp) || die;

				}

			}

		}

	}

	$dbh->commit;

	print "\n"		if $DEBUG;

}

