#!/bin/bash

cd $(dirname $0)

for a in $(psql dipa -XAtc 'select code from countries'); do 
	./update-prices.pl $a &
	sleep 20
done

wait
