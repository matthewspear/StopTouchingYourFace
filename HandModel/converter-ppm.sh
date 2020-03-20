#!/usr/bin/env bash

for i in  {1..302}
do
  convert $i.jpg $i.ppm
done
