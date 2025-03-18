#!/bin/bash

if [ -z $1 ]; then
	git diff main --name-status | awk '{ print NR " " $0 }'
else
	name="`git diff main --name-only | head -n $1 | tail -n 1`"
	git diff main $name
fi