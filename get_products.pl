#!/usr/bin/perl -w

use Cpanel::JSON::XS;
use DBI;
use Mojo::UserAgent;
use Encode;
use Data::Dumper;
use utf8;

my $DEBUG = 1;

my $dbh = DBI->connect("dbi:Pg:dbname=dipa") || die;
my $ua = Mojo::UserAgent->new;
$ua->inactivity_timeout(300);

$coder = Cpanel::JSON::XS->new->allow_nonref;

get_channels();

read_prod_info();

# get_info("9MW581HCJPM6");		# Evil West
# get_info("9MTLKM2DJMZ2");		# Forza Horizon 5 Premium Edition

$dbh->disconnect;

#######################

sub read_prod_info {

	my @all = map { $_ -> [0] } $dbh->selectall_array("select bigid from products group by 1 order by random()");

	while( my @slice = splice(@all, 0, 99) ) {

		my $str = join ',', @slice;
		get_info($str);

		# last;

	}

}

sub get_info {

	my $str = shift;
	print "$str\n\n";

	my $json = $ua->get("https://displaycatalog.mp.microsoft.com/v7.0/products?".
		"bigIds=$str&market=Neutral&languages=en-us&MS-CV=DGU1mcuYo0WMMp+F.1")->result->json;

	foreach $pr (@{$json->{Products}}) {

		my $bigid     = $pr->{'ProductId'};
		my $developer = $pr->{LocalizedProperties}->[0]->{DeveloperName};
		my $publisher = $pr->{LocalizedProperties}->[0]->{PublisherName};
		my $type      = $pr->{ProductType};
		my $name      = $pr->{LocalizedProperties}->[0]->{ProductTitle};

		my $released  = $pr->{MarketProperties}->[0]->{OriginalReleaseDate};
		my $category  = $pr->{Properties}->{Category};
		my @categories = $pr->{Properties}->{Categories};
		my @optimized  = $pr->{Properties}->{XboxConsoleGenOptimized};
		my @compatible = $pr->{Properties}->{XboxConsoleGenCompatible};
		my $attributes = $pr->{Properties}->{Attributes};

		$dbh->do('insert into products(released,bigid,name,type,developer,publisher,category,categories,optimized,compatible,attributes) 
			values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) on conflict(bigid) do update
			set released=$1,name=$3,type=$4,developer=$5,publisher=$6,category=$7,categories=$8,optimized=$9,compatible=$10,attributes=$11', undef,
			$released,$bigid,$name,$type,$developer,$publisher,$category,\@categories,\@optimized,\@compatible, $coder->encode($attributes));

		foreach $s (@{$pr->{DisplaySkuAvailabilities}}) {

			my $sku = $s->{Sku};
			my $skuid = $sku->{SkuId};
			my $skutype = $sku->{SkuType};
			my $skuname = $sku->{LocalizedProperties}->[0]->{SkuTitle};
			my $bundled = $sku->{Properties}->{BundledSkus};
			$dbh->do('insert into skus(bigid,skuid,skuname,skutype,bundledskus) values($1,$2,$3,$4,$5) on conflict(bigid,skuid) do update
				set skuname=$3,skutype=$4,bundledskus=$5', undef, $bigid, $skuid, $skuname, $skutype, $coder->encode($bundled));

		}

	}

}


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

