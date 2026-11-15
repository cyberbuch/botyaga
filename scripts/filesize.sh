#!/usr/bin/env bash
# Размери на модулите: мек gate 400 реда, твърд 600.
# Дългият файл се дели на модули с header-и, не се съкращава с коментари.
set -u

soft=400
hard=600
over_hard=0

while IFS= read -r file; do
  lines=$(wc -l < "$file")
  if [ "$lines" -gt "$hard" ]; then
    echo "ТВЪРДО ПРЕВИШЕН ($lines > $hard): $file"
    over_hard=1
  elif [ "$lines" -gt "$soft" ]; then
    echo "предупреждение ($lines > $soft): $file"
  fi
done < <(find lib test -name '*.ex' -o -name '*.exs' | sort)

exit "$over_hard"
