#!/usr/bin/env bash

function cleanup()
{
    echo "👋 Bye"
}

trap cleanup EXIT

for i in a b c;
do
    echo "i is $i"
    sleep 1
done