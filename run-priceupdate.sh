#!/bin/bash

# change dir to dpa so that nohup.out was there
cd $(dirname $0)

for a in ca gb co jp kr us "fi"; do 
	nohup ./update-prices.pl $a 2> /dev/null &
done

wait
