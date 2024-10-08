# dipa

Xbox.com store scanner. Contains 2 perl scripts:

## get_products.pl

Reads product information in "Neutral" market

## update-prices.pl

Updates prices for the region

## run-priceupdate.sh

Updates prices for selected regions in parallel

## schema.sql

This is PostgreSQL schema for "dipa" database

## crontab example

```
07	6,18	*	*	*	./dipa/get_products.pl
0	0,12	*	*	*	./dipa/run-priceupdate.sh
```


