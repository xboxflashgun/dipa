#!/bin/bash

cd $(dirname $0)

for a in $(psql dipa -XAtc 'select code from countries'); do 
	./update-prices.pl $a &
done

wait
