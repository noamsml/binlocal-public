#!/bin/bash

if [ -z $1 ]; then
	git diff master --name-status | awk '{ print NR " " $0 }'
else
	name="`git diff master --name-only | head -n $1 | tail -n 1`"
	git diff master $name
fi