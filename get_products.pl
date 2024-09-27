#!/usr/bin/perl -w

use Cpanel::JSON::XS;
use DBI;
use Mojo::UserAgent;
use Encode;
use Data::Dumper;

my $DEBUG = 1;

my $dbh = DBI->connect("dbi:Pg:dbname=dipa") || die;
my $ua = Mojo::UserAgent->new;
$ua->inactivity_timeout(300);

get_channels();


$dbh->disconnect;

#######################

sub get_channels {

	my @chans = qw (
		Collection/DealsWithGold computed/ComingSoon computed/New Collection/GamesWithGold
		computed/TopPaid computed/TopFree computed/MostPlayed
	);

	my @types = qw ( Game Application Durable UnmanagedConsumable Consumable PASS AvatarItem );

	foreach $type (@types) {
	foreach $chan (@chans) {

		print " * Reading $chan channel for $type\n"       if( $DEBUG );

		my $si = 0;
		my $count = 2000;
		my $total = 1;

		while($si < $total) {

			my $json = $ua->get("https://reco-public.rec.mp.microsoft.com/channels/Reco/V8.0/Lists/$chan".
				"?itemTypes=$type&DeviceFamily=Windows.Xbox&count=$count&clientType=XboxApp&market=Neutral&".
				"PreferredLanguages=en-US,ru&skipItems=$si")->result->json;

			foreach $item (@{$json->{Items}}) {

				my $bigid = uc($item->{Id});
				if(not defined $dbh->selectrow_array("select 1 from products where bigid=?", undef, $bigid)) {

					$dbh->do("insert into products(bigid) values(?)", undef, $bigid);

				}

			}

			$total = $json->{PagingInfo}->{TotalItems};
			last if not defined $total;

			$si += $count;

		}

	}
	}

}

