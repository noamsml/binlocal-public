#!/bin/bash

if echo "$1" | grep -e "^aws" > /dev/null; then
    kubectl config use-context "$1"
    KUBE_CONTEXT="$1"
    shift 1
else
    KUBE_CONTEXT=$(kubectl config current-context)
fi

echo -e "\033[1;34mUsing context: $KUBE_CONTEXT\033[0m"
echo 

if [ -z "$*" ]; then
    exit 0
fi

kubectl "$@"