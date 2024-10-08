#!/bin/bash

# change dir to dpa so that nohup.out was there
cd $(dirname $0)

rm nohup.out

for a in ca gb co jp kr us "fi" ar tr za; do 
	nohup ./update-prices.pl $a 2> /dev/null &
done

wait
