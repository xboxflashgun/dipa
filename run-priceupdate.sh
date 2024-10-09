#!/bin/bash

cd $(dirname $0)

for a in ca gb co jp kr us "fi" ar tr za; do 
	./update-prices.pl $a &
done

wait
