#!/bin/bash
name=""
if [[ "$2" != "" ]]; then
  name="$2"
fi

allowlist=""
first=1
second=1
third=1
forth=1
for i in $(seq 1 $1); do
  if [[ $forth -ge 255 ]]; then
    if [[ $third -ge 255 ]]; then
      if [[ $second -ge 255 ]]; then
        if [[ $first -ge 255 ]]; then
          echo "ERROR LIMIT"
	  exit 1
	fi
	first=$((first+1))
	second=1
	third=1
	forth=1
        echo -n "${first}.${second}.${third}.${forth}/32, "
	continue
      fi
      second=$((second+1))
      third=1
      forth=1
      echo -n "${first}.${second}.${third}.${forth}/32, "
      continue
    fi
    third=$((third+1))
    forth=1
    echo -n "${first}.${second}.${third}.${forth}/32, "
    continue
  fi
  forth=$((forth+1))
  echo -n "${first}.${second}.${third}.${forth}/32, "
done

echo "allowlist.txt${name} generated"
