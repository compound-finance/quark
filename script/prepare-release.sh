#!/bin/bash

set -eo pipefail

command -v gh   || >&2 printf 'FATAL: "gh" command (github cli) not found\n'
command -v zip  || >&2 printf 'FATAL: "zip" command not found\n'
command -v date || >&2 printf 'FATAL: "date" command not found\n'

version_hash=$(git rev-parse --short HEAD)
release_date=$(date +'%Y-%m-%d') # year-month-day
release_name="release-v${release_date}+${version_hash}"

artifact_name="quark-out.${release_name}.zip"
artifact_note="Compiled ABI"

printf 'preparing release archive "%s"...\n' ${release_name}
zip "${artifact_name}" out/*

# `gh release view` defaults to the 'latest' release
previous_release_tag=$(gh release view --json tagName --jq '.tagName' || :)

printf 'creating release and uploading archive...\n'

flags="--generate-notes"
if [[ -n "${previous_release_tag}" ]]; then
  flags="${flags} --notes-start-tag ${previous_release_tag}"
fi

set -x
gh release create ${flags} "${release_name}" "${artifact_name}#${artifact_note}"

rm "${artifact_name}"
