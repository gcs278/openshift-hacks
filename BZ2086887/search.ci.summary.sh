#!/bin/bash

curl -s 'https://search.ci.openshift.org/search?maxAge=36h&type=build-log&context=0&search=dial+tcp%3A+lookup.*i%2Fo+timeout&search=Using+namespace+https' | jq -r 'to_entries[].value | (length | tostring) as $len | (.["Using namespace https"] // [])[].context[] | . + " " + $len' | sed 's/.*\(build[0-9]*\).* \([0-9]*\)$/\1 \2/' | sort | uniq -c
