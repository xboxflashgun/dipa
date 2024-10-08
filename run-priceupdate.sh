#!/bin/bash

for a in ca gb co jp kr us; do 
	nohup ./update-prices.pl $a & 
done

wait
