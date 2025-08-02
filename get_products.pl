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
my %bc;		# backward compatibility hash

my $dbh = DBI->connect("dbi:Pg:dbname=dipa") || die;
my $ua = Mojo::UserAgent->new;
$ua->inactivity_timeout(300);

my $coder = Cpanel::JSON::XS->new->allow_nonref;

# get_info("9MW581HCJPM6");		# Evil West
# get_info("9MTLKM2DJMZ2");		# Forza Horizon 5 Premium Edition
# get_info("CFQ7TTC0P85B,CFQ7TTC0HX8W,CFQ7TTC0QH5H,CFQ7TTC0KGQ8,CFQ7TTC0KHS0");
# get_info("BVZ4H08BMQ3H");	# Rockstar Table Tennis
# get_info('C54XLS381SXJ');
# get_info('C5FVH1MHKL4W');
# exit;

# internal: remove this
get_xboxstat();

get_channels();

scan_all_games();

read_x360bc();

read_prod_info();

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

sub get_xboxstat	{

	my $dbg = DBI->connect("dbi:Pg:dbname=global;port=6432") || die;
	my @titleids = map { $_ -> [0] } $dbg->selectall_array("select titleid from games where name is null or name ='' or name like 'titleid_%'");

	print "Total ", scalar(@titleids), " unknown titleids\n"		if $DEBUG;
	
	for $t (@titleids)	{

		my $json = $ua->get("https://displaycatalog.md.mp.microsoft.com/v7.0/products/lookup"
			."?market=US&languages=en-US,ru&alternateId=XboxTitleId&value=$t&%24top=25&fieldsTemplate=details")->result->json;

		my $bigid = $json->{'Products'}->[0]->{'ProductId'};
		print "$t\e[K\r"				if $DEBUG;
		sleep 1 if $t % 13 == 4;
		next if not defined $bigid;
		print "$t: $bigid\e[K\n"		if $DEBUG;
		my $type = $json->{'Products'}->[0]->{'ProductType'};
		my $name = $json->{'Products'}->[0]->{'LocalizedProperties'}->[0]->{'ProductTitle'};
		$dbg->do("update games set name=?,isgame=(?='Game') where titleid=?", undef, $name, $type, $t);
		$dbh->do("insert into products(bigid) values(?) on conflict do nothing", undef, $bigid);

	}

	$dbg->disconnect;

}

#######################

sub read_x360bc	{

	print " * Reading Xbox360 backward compatibility list\n"	if $DEBUG;

	my $json = $ua->get("https://settings.data.microsoft.com/settings/v2.0/xbox/backcompatcatalogidmapall?scenarioid=all")->result->json;

	$dbh->begin_work;
	foreach $row (keys %{$json->{settings}}) {

		$dbh->do('insert into bc360list(legacyid,bingid) values($1,$2) on conflict(legacyid) do update set bingid=$2', undef, $row, $json->{settings}{$row});
		$bc{lc($row)} = lc($json->{settings}{$row});

	}
	$dbh->commit;

}

sub read_prod_info {

	my @all = map { $_ -> [0] } $dbh->selectall_array("select bigid from products order by random()");

	while( my @slice = splice(@all, 0, int(900+rand(98))) ) {

		my $str = join ',', @slice;
		print " * Slice size: ", scalar(@slice) 	if $DEBUG;
		get_info($str);
		sleep 1;

	}

}

sub read_new_prods {

	my @all = map { $_ -> [0] } $dbh->selectall_array("select bigid from products where type is null order by random()");

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
		my $titleid    = (grep { $_->{IdType} eq 'XboxTitleId' } @{$pr->{AlternateIds}})[0]->{Value}
			if(grep { $_->{IdType} eq 'XboxTitleId' } @{$pr->{AlternateIds}});

		$released = '2000-01-01'	if( !defined($released) || $released eq '' );
		
		# Xbox 360 backward compatibility flag
		my $xbox360 = 0;
		my @leg = grep { $_->{IdType} eq 'LegacyXboxProductId' } @{$pr->{AlternateIds}};
		foreach $legid (@leg) {

			$xbox360 = 1	if(defined($bc{$legid->{Value}}));

		}

		$dbh->do('
			insert into products(released,bigid,name,type,developer,publisher,category,categories,optimized,
				compatible,attributes,relatedprods,xbox360,titleid) 
				values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) on conflict(bigid) do update
				set released=$1,name=$3,type=$4,developer=$5,publisher=$6,category=$7,categories=$8,optimized=$9,
					compatible=$10,attributes=$11,relatedprods=$12,xbox360=$13,titleid=$14', 
			undef,$released,$bigid,$name,$type,$developer,$publisher,$category,\@categories,\@optimized,\@compatible, 
			$coder->encode($attributes), $coder->encode($relprods),$xbox360, $titleid)
				|| die;

		# Reading UsageData
		my @oldusage = $dbh->selectall_array('select distinct usagedate,timespan,ratecnt,rating from usagedata where bigid=$1 order by usagedate',
			undef, $bigid);
		
		my %rates;
		my %cnts;
		for $u (@oldusage) {

			$rates{$u->[1]} = $u->[3];
			$cnts{$u->[1]} = $u->[2];

		}

		foreach $mp (@{$pr->{MarketProperties}->[0]->{UsageData}}) {

			my $timespan = $mp->{AggregateTimeSpan};
			my $rating   = $mp->{AverageRating};
			my $ratecnt  = $mp->{RatingCount};

			if(not defined $rates{$timespan} or not defined $cnts{$timespan} or $rates{$timespan} != $rating or $cnts{$timespan} != $ratecnt) {

				$dbh->do('insert into usagedata(usagedate,bigid,timespan,rating,ratecnt) values(now()::date,$1,$2,$3,$4)
					on conflict(usagedate,bigid,timespan) do update set rating=$3,ratecnt=$4', undef, $bigid, $timespan, $rating, $ratecnt);

			}

		}

		# Reading images
		foreach $img (@{$pr->{LocalizedProperties}->[0]->{Images}}) {

			my $width  = $img->{Width};
			my $height = $img->{Height};
			my $fsize  = $img->{FileSizeInBytes};
			my $purp   = $img->{ImagePurpose};
			my $uri    = $img->{Uri};
			my $posit  = $img->{ImagePositionInfo};

			$posit = "" if not defined $posit;

			$dbh->do('insert into images(width,height,filesize,bigid,purpose,uri,position) values($1,$2,$3,$4,$5,$6,$7) 
				on conflict(bigid,purpose) do update set width=$1,height=$2,filesize=$3,uri=$6,position=$7', undef,
				$width, $height, $fsize, $bigid, $purp, $uri, $posit);

		}

		# Reading actual SKUs
		$dbh->do('delete from skus where bigid=$1', undef, $bigid);
		foreach $s (@{$pr->{DisplaySkuAvailabilities}}) {

			my $sku = $s->{Sku};
			my $skuid = $sku->{SkuId};
			my $skutype = $sku->{SkuType};
			my $skuname = $sku->{LocalizedProperties}->[0]->{SkuTitle};
			my $bundled = $sku->{Properties}->{BundledSkus};
			$dbh->do('insert into skus(bigid,skuid,skuname,skutype,bundledskus) values($1,$2,$3,$4,$5)', undef, 
				$bigid, $skuid, $skuname, $skutype, $coder->encode($bundled)) 	|| die;

		}

	}
	$dbh->commit;

}


sub get_channels {

	my @chans = qw (
f13cf6b4-57e6-4459-89df-6aec18cf0538
fc40d1b9-85ec-422d-b454-8685fb31776e
fafb048d-9850-4447-ae20-f8f698bd208a
3b2da8c2-a0b0-49d5-aab9-f0ac40beb43d
34031711-5a70-4196-bab7-45757dc2294e
09a72c0d-c466-426a-9580-b78955d8173a
099d5213-25e2-4896-bf09-33432f1c6e66
c76e2ddb-345d-4483-981e-d90789fcb46b
f13cf6b4-57e6-4459-89df-6aec18cf0538
fc40d1b9-85ec-422d-b454-8685fb31776e
fafb048d-9850-4447-ae20-f8f698bd208a
8e7cd765-1293-44e0-95bb-8257e2bf0221
393f05bf-e596-4ef6-9487-6d4fa0eab987
6182c1f2-11b0-4df1-890e-f940fbe33493
3fdd7f57-7092-4b65-bd40-5a9dac1b2b84
d545e21a-d165-4f3f-a95b-b08542b0d2ec
4165f752-d702-49c8-886b-fb57936f6bae
83e4b73e-d89c-4b95-8c63-17cdd4b5a7b3
a884932a-f02b-40c8-a903-a008c23b1df1
2e8e2cdf-f1bb-4e7e-8295-04949a26f6cc
1e2ce757-e84f-4d2c-9243-34b81912644a
c621daed-3d22-4745-afc9-19ed77a2e9be
9fd6a075-57c3-4084-82d0-b00e2d43424a
25d0b8d5-1a6a-489f-8195-219c96656497
0f0bccc0-cdc8-4e1a-bfca-4b7da5c6c418
cc7fc951-d00f-410e-9e02-5e4628e04163
f6f1f99f-9b49-4ccd-b3bf-4d9767a77f5e
f6f1f99f-9b49-4ccd-b3bf-4d9767a77f5e
e7590b22-e299-44db-ae22-25c61405454c
29a81209-df6f-41fd-a528-2ae6b91f719c
88c10a22-33b5-4e24-90b6-125bee02da39
ebedc400-a688-4929-b794-4435b2e1ab0a
f576ca76-9aad-4ac7-a0f0-71429ef36850
c4be032d-0f42-4df5-8934-1758748cf7f0
95f39cf3-48ec-4d3c-83e6-a7f6916fbdfe
e68225ce-e42f-4156-998d-697bf985da73
38441e3f-26c6-498c-8b84-0ca20a3785af
200674bd-7bd4-4360-bd0f-af8cd899839f
5d6c2384-b30e-4717-86f6-e684e819622b
7d8e8d56-c02f-4711-afec-73a80d8e9261
796c328b-4a17-4996-99f8-0edb59bef85a
6661f37d-6159-4c9c-81d8-668af0a78b04
18e0b0af-cefe-4492-845c-b9f6ab8737f8
b8900d09-a491-44cc-916e-32b5acae621b
b8900d09-a491-44cc-916e-32b5acae621b
eab7757c-ff70-45af-bfa6-79d3cfb2bf81
095bda36-f5cd-43f2-9ee1-0a72f371fb96
a672552e-fdc2-4ecd-96e9-b8409193f524
4b59700c-801f-494a-a34c-842b8c98f154
609d944c-d395-4c0a-9ea4-e9f39b52c1ad
a5a535fb-d926-4141-9ce4-9f6af8ca22e7
9c09d734-1c45-4740-ae7f-fd73ff629880
490f4b6e-a107-4d6a-8398-225ee916e1f2
19e5b90a-5a20-4b1d-9dda-6441ca632527
4e641124-9279-46a5-a73f-4e20d89c787c
4e641124-9279-46a5-a73f-4e20d89c787c
f6505a9f-ec7d-4eb8-a496-be83f8f35829
79fe89cf-f6a3-48d4-af6c-de4482cf4a51
0ee8fddb-8a59-45c5-aebb-9d4adbe832c5
1d33fbb9-b895-4732-a8ca-a55c8b99fa2c
4c894453-744d-4b35-acea-40df9f4312b1
5dfd8fdd-2fd3-4e7f-b9f8-175e96b1adac
7dff3157-a037-4449-85db-8086d51ec4f8
62ba1846-03bb-4209-aeea-35110a9935f1
39d48297-93f9-4b5a-85dd-641a337b212c
6d18c7d7-7f62-4c87-b1b7-b5555c5752d0
0767da77-95d4-4023-9971-d1a9756fccef
bd8e0e95-78d1-42fd-aee2-291210df273d
15d529d7-0b6b-431f-a0fe-fa01d6a6e9c6
3950236c-9aa7-433d-88fd-96023d276346
f0e9ffe0-176e-41af-be11-c40a05d26e2c
f4e1445f-89fb-42ca-ab12-bc06039d9927
3a6b073e-9719-4071-b7a3-6d836f5d949e
	);

	foreach $chan (@chans) {

		my $json = $ua->get("https://catalog.gamepass.com/sigls/v2?id=$chan&language=ru-ru&market=US")->result->json;
		my $cnt = 0;

		foreach $item (@{$json})       {

			if($item->{id})  {

				my $bigid = $item->{id};
				$cnt += $dbh->do("insert into products(bigid) values(?) on conflict(bigid) do nothing", undef, $bigid);

			}

		}

	}


}

sub scan_all_games	{

	my ($total, $skip, $ct);
	my $cnt = 0;

	do {
		my $filter = {
			'ChannelId' => '',
			'ChannelKeyToBeUsedInResponse' => 'BROWSE_CHANNELID=_FILTERS=PLAYWITH=XBOXONE,XBOXSERIESX|S',
			'ReturnFilters' => 0,
		};

		if($ct) {
			$filter->{'EncodedCT'} = $ct;
		}

		my $json = $ua->post("https://emerald.xboxservices.com/xboxcomfd/browse?locale=en-US" => {
				'Accept' => '*/*',
				'Accept-Language' => 'en-US,en;q=0.7,ru;q=0.3',
				'content-type' => 'application/json',
				'ms-cv' => 'Wgq+d2EbI67rsD/CszUB1S.49',
				'Priority' => 'u=4',
				'TE' => 'trailers',
				'x-ms-api-version' => '1.1',
			} => json => $filter)->result->json;

		my $chan = $json->{channels}->{'BROWSE_CHANNELID=_FILTERS=PLAYWITH=XBOXONE,XBOXSERIESX|S'};

		$ct = $chan->{encodedCT};
		$total = $chan->{totalItems};

		foreach $p (@{$chan->{products}}) {

			my $bigid = $p->{productId};
			$cnt += $dbh->do("insert into products(bigid) values(?) on conflict(bigid) do nothing", undef, $bigid);

		}

	} while($ct);

}



