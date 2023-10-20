#!/bin/bash
name=""
if [[ "$2" != "" ]]; then
  name="$2"
fi

base="2001:0000:130F:0000:0000:09C0:876A:"

rm whitelist.txt${name}
whitelist=""
for i in $(seq 1 $1); do
  echo "${base}$(printf '%04x\n' $i)/128" >> whitelist.txt${name}
done

echo "whitelist.txt${name} generated"
