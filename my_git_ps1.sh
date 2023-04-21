#!/bin/bash

GIT_BASE="$(git rev-parse --show-toplevel 2>/dev/null)"
CURRENT_DIR="$(pwd)"


function git_prompt_part () {
	if [ "$CURRENT_DIR" != "$GIT_BASE" ]; then
		if [ "$(dirname "$CURRENT_DIR")" = "$GIT_BASE" ]; then
			SUBDIR_PART="/$(basename "$CURRENT_DIR")"
		else
			SUBDIR_PART="/.../$(basename "$CURRENT_DIR")"
		fi
	fi

	if [ "$GIT_PS1_SHOWDIRTYSTATE" ]; then
		STATUS="$(git status -uno -s)"

		if [ "$STATUS" ]; then
			STATUS_PART=" *"
		else
			STATUS_PART=""
		fi
	else 
		STATUS_PART=" @"
	fi

	echo "$(basename $GIT_BASE)$SUBDIR_PART $(branch)$STATUS_PART"
}

function nongit_prompt_part () {
	echo "$(basename $CURRENT_DIR)"
}

if [ "$GIT_BASE" ]; then
	git_prompt_part
else
	nongit_prompt_part
fi

