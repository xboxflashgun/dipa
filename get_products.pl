#!/usr/bin/perl -w

# fix for "Maximum header size exceeded"
$ENV{MOJO_MAX_LINE_SIZE} = 32768;

use Cpanel::JSON::XS;
use DBI;
use Mojo::UserAgent;
use Encode;
use Data::Dumper;
use utf8;

$|++;
# my $DEBUG = 1;

my $dbh = DBI->connect("dbi:Pg:dbname=dipa") || die;
my $ua = Mojo::UserAgent->new;
$ua->inactivity_timeout(300);

$coder = Cpanel::JSON::XS->new->allow_nonref;

get_channels();

read_x360bc();

read_prod_info();

# get_info("9MW581HCJPM6");		# Evil West
# get_info("9MTLKM2DJMZ2");		# Forza Horizon 5 Premium Edition

# New products scan
print "New products scan:\n"	if $DEBUG;

while( $dbh->do("
	insert into products(bigid) (
		select distinct(pr->>'RelatedProductId') as bid from products,jsonb_array_elements(relatedprods) pr
			union
		select distinct(b->>'BigId') as bid from skus,jsonb_array_elements(bundledskus) b where jsonb_typeof(bundledskus)='array')
	on conflict do nothing") > 0 ) {

	read_new_prods();

}


$dbh->disconnect;

#######################

sub read_x360bc	{

	print " * Reading Xbox360 backward compatibility list\n"	if $DEBUG;

	my $json = $ua->get("https://settings.data.microsoft.com/settings/v2.0/xbox/backcompatcatalogidmapall?scenarioid=all")->result->json;

	$dbh->begin_work;
	foreach $row (keys %{$json->{settings}}) {

		$dbh->do('insert into bc360list(legacyid,bingid) values($1,$2) on conflict(legacyid) do update set bingid=$2', undef, $row, $json->{settings}{$row});

	}
	$dbh->commit;

}

sub read_prod_info {

	my @all = map { $_ -> [0] } $dbh->selectall_array("select bigid from products group by 1 order by random()");

	while( my @slice = splice(@all, 0, int(900+rand(98))) ) {

		my $str = join ',', @slice;
		print " * Slice size: ", scalar(@slice) 	if $DEBUG;
		get_info($str);
		sleep 1;

	}

}

sub read_new_prods {

	my @all = map { $_ -> [0] } $dbh->selectall_array("select bigid from products where type is null group by 1 order by random()");

	while( my @slice = splice(@all, 0, 997) ) {

		my $str = join ',', @slice;
		print " * Slice size: ", scalar(@slice) 	if $DEBUG;
		get_info($str);
		sleep 1;

	}

}

sub get_info {

	my $str = shift;

	my $json = $ua->get("https://displaycatalog.mp.microsoft.com/v7.0/products?".
		"bigIds=$str&market=Neutral&languages=en-us&MS-CV=DGU1mcuYo0WMMp+F.1")->result->json;

	print "\n" 		if $DEBUG;

	$dbh->begin_work;
	foreach $pr (@{$json->{Products}}) {

		my $bigid     = $pr->{'ProductId'};
		my $developer = $pr->{LocalizedProperties}->[0]->{DeveloperName};
		my $publisher = $pr->{LocalizedProperties}->[0]->{PublisherName};
		my $type      = $pr->{ProductType};
		my $name      = $pr->{LocalizedProperties}->[0]->{ProductTitle};

		my $released  = $pr->{MarketProperties}->[0]->{OriginalReleaseDate};
		my $relprods  = $pr->{MarketProperties}->[0]->{RelatedProducts};
		my $category  = $pr->{Properties}->{Category};
		my @categories = $pr->{Properties}->{Categories};
		my @optimized  = $pr->{Properties}->{XboxConsoleGenOptimized};
		my @compatible = $pr->{Properties}->{XboxConsoleGenCompatible};
		my $attributes = $pr->{Properties}->{Attributes};

		$released = '2000-01-01'	if( !defined($released) || $released eq '' );

		$dbh->do('
			insert into products(released,bigid,name,type,developer,publisher,category,categories,optimized,compatible,attributes,relatedprods) 
				values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) on conflict(bigid) do update
				set released=$1,name=$3,type=$4,developer=$5,publisher=$6,category=$7,categories=$8,optimized=$9,
					compatible=$10,attributes=$11,relatedprods=$12', 
			undef,$released,$bigid,$name,$type,$developer,$publisher,$category,\@categories,\@optimized,\@compatible, 
			$coder->encode($attributes), $coder->encode($relprods))
				|| die;


		foreach $s (@{$pr->{DisplaySkuAvailabilities}}) {

			my $sku = $s->{Sku};
			my $skuid = $sku->{SkuId};
			my $skutype = $sku->{SkuType};
			my $skuname = $sku->{LocalizedProperties}->[0]->{SkuTitle};
			my $bundled = $sku->{Properties}->{BundledSkus};
			$dbh->do('insert into skus(bigid,skuid,skuname,skutype,bundledskus) values($1,$2,$3,$4,$5) on conflict(bigid,skuid) do update
				set skuname=$3,skutype=$4,bundledskus=$5', undef, $bigid, $skuid, $skuname, $skutype, $coder->encode($bundled)) 
					|| die;

		}

	}
	$dbh->commit;

}


sub get_channels {

	my @chans = qw (
		Collection/DealsWithGold computed/ComingSoon computed/New Collection/GamesWithGold
		computed/TopPaid computed/TopFree computed/MostPlayed
	);

	my @types = qw ( Game Application Durable UnmanagedConsumable Consumable PASS AvatarItem );

	foreach $type (@types) {
	foreach $chan (@chans) {

		print " * Reading $chan channel for $type: "       if( $DEBUG );

		my $si = 0;
		my $count = 2000;
		my $total = 1;
		my $new = 0;

		while($si < $total) {

			my $json = $ua->get("https://reco-public.rec.mp.microsoft.com/channels/Reco/V8.0/Lists/$chan".
				"?itemTypes=$type&DeviceFamily=Windows.Xbox&count=$count&clientType=XboxApp&market=Neutral&".
				"PreferredLanguages=en-US,ru&skipItems=$si")->result->json;

			foreach $item (@{$json->{Items}}) {

				my $bigid = uc($item->{Id});
				if(not defined $dbh->selectrow_array("select 1 from products where bigid=?", undef, $bigid)) {

					$new += $dbh->do("insert into products(bigid) values(?)", undef, $bigid);

				}

			}

			$total = $json->{PagingInfo}->{TotalItems};
			last if not defined $total;

			$si += $count;

		}

		print "$new\n"	if( $DEBUG );

	}
	}

}

