# dipa

Xbox.com store scanner. Contains 2 perl and 1 bash script:

## get_products.pl

Reads product information in "Neutral" market. Fills "products" table with items' properties.

## update-prices.pl

Updates prices for the region.

## run-priceupdate.sh

Updates prices for selected regions in parallel.

## schema.sql

This is PostgreSQL schema for "dipa" database. I believe PostgreSQL 12+ is enough for my scripts.

## crontab example

```
07	6,18	*	*	*	./dipa/get_products.pl
0	0,12	*	*	*	./dipa/run-priceupdate.sh
```


