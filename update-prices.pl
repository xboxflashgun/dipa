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

$coder = Cpanel::JSON::XS->new->allow_nonref;

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

# remove expired prices
$dbh->do('delete from prices where enddate < now() and region=$1', undef, $market);

# update "exrates" table with currency exchange rates
update_exrates();

$dbh->disconnect;


##########################################

sub get_prices {

	my $str = shift;

	my $json = $ua->get("https://displaycatalog.mp.microsoft.com/v7.0/products?".
		"bigIds=$str&market=$market&languages=en&MS-CV=$mscv")->result->json;

	$dbh->begin_work;

	foreach $pr (@{$json->{Products}}) {

		my $bigid = $pr->{'ProductId'};
		$dbh->do('delete from prices where bigid=$1 and region=$2', undef, $bigid, $market);

		for $sku (@{$pr->{'DisplaySkuAvailabilities'}}) {

			my $skuid = $sku->{'Sku'}->{'SkuId'};
			my $skutype = $sku->{'Sku'}->{'SkuType'};

			for $av (@{$sku->{'Availabilities'}})   {

				my $plt;	# platform shoud be Windows.Xbox
				for $pl (@{$av->{'Conditions'}->{'ClientConditions'}->{'AllowedPlatforms'}})    {

					$plt = 1          if($pl->{'PlatformName'} eq 'Windows.Xbox');

				}
				next if not defined $plt;

				my $lastmod = $av->{LastModifiedDate};
				my $msrpp = $av->{'OrderManagementData'}->{'Price'}->{'MSRP'};
				my $listp = $av->{'OrderManagementData'}->{'Price'}->{'ListPrice'};

				if( grep { /Purchase/ } @{$av->{'Actions'}} )	{

					my $stdate  = $av->{Conditions}->{StartDate};
					my $enddate = $av->{Conditions}->{EndDate};
					my $remid = '';

					$remid = $av->{Remediations}->[0]->{BigId}	if( $av->{RemediationRequired} );

					$dbh->do('insert into prices(bigid,skuid,region,remid,stdate,enddate,msrpp,listprice,lastmodified) values($1,$2,$3,$4,$5,$6,$7,$8,$9)
						on conflict(bigid,skuid,region,remid,stdate) do nothing', undef,
						$bigid, $skuid, $market, $remid, $stdate, $enddate, $msrpp, $listp, $lastmod) || die;

					# update price history
					my @last = $dbh->selectrow_array('select stdate,msrpp,listprice from pricehistory where bigid=$1 and skuid=$2 and region=$3 
						and remid=$4 order by stdate limit 1', undef, $bigid, $skuid, $market, $remid);

					if(scalar(@last) == 0 || $msrpp != $last[1] || $listp != $last[2]) {

						$dbh->do('insert into pricehistory(stdate,bigid,skuid,region,remid,msrpp,listprice,ndays) values($1::timestamp,$2,$3,$4,$5,$6,$7,
							extract(days from now()-$1)) on conflict do nothing', undef, $stdate, $bigid, $skuid, $market, $remid, $msrpp, $listp) || die;

					} else {

						$dbh->do('update pricehistory set ndays=extract(days from now()-stdate) where bigid=$1 and skuid=$2 and region=$3 and remid=$4
								and stdate=$5', undef, $bigid, $skuid, $market, $remid, $last[0]);

					}

				}

			}

		}

	}

	$dbh->commit;

	print "\n"		if $DEBUG;

}


#############################################
# https://github.com/fawazahmed0/exchange-api

sub update_exrates {

	my @curs  = $dbh->selectall_array("select distinct cur from countries order by cur");
	foreach $c (@curs) {

		my $cur = lc($c->[0]);
		my @dates = $dbh->selectall_array('
			select a::date 
			from 
				generate_series(
					(select max(exdate) from exrates where cur=$1)::timestamp,
					now(),
					interval \'1 day\') a', undef, uc($cur));
	
		foreach $d (@dates) 	{

			my $date = $d->[0];
			get_exrate($date,$cur);
			sleep 3;
	
		}
	
	}

}

sub get_exrate {

	my ($date, $base) = @_;
	$base = lc($base);

	my $json = $ua->get("https://cdn.jsdelivr.net/npm/\@fawazahmed0/currency-api\@$date/v1/currencies/$base.json")->result->json;

	if( ! defined($json) ) {

		# Fallback
		$json = $ua->get("https://$date.currency-api.pages.dev/v1/currencies/$base.json")->result->json;

	}

	# print "Warn: unable to get currency exchange rates for '$base' at $date\n" if not defined $json;
	return if not defined $json;

	$dbh->do('insert into exrates(exdate,cur,exrates) values($1,$2,$3) on conflict(exdate,cur) do update set exrates=$3', undef, $date, uc($base), $coder->encode($json->{$base}));

}
