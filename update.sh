#!/usr/bin/env bash
set -Eeuo pipefail


if ! [ -x "$(command -v j2)" ]; then
  echo 'Error: j2 is not installed.' >&2
  echo 'Install using "pip install j2cli[yaml]"' >&2
  exit 1
fi

me=`basename "$0"`

versions=( */ )
versions=( "${versions[@]%/}" )

travisEnv=
echo "entries:" > build.yml
for version in "${versions[@]}"; do
    if [[ "$version" == "files" || "$version" == "venv" ]]; then
    continue
    fi

    rcVersion="${version%-rc}"

    echo $version

    # "7", "5", etc
    majorVersion="${rcVersion%%.*}"
    # "2", "1", "6", etc
    minorVersion="${rcVersion#$majorVersion.}"
    minorVersion="${minorVersion%%.*}"

    dockerfiles=()

    baseDockerfile=files/templates/Dockerfile.j2

    for variant in cli apache fpm; do
        [ -d "$version/$variant" ] || continue

        for debug in debug no-debug; do
            mkdir -p "$version/$variant/$debug"
            export version
            export variant
            export debug
            echo "Generating $version/$variant/$debug/Dockerfile from $baseDockerfile"
            j2 $baseDockerfile > $version/$variant/$debug/Dockerfile
            

            if [ -d "files/$variant/" ]; then
                echo "processing files for $variant"
                while IFS= read -r -d $'' file; do
                    j2 "$file" > "$version/$variant/$debug/$(basename $file)"
                done < <(find files/$variant -maxdepth 1 -type f  -print0)
            fi

            if [ -d "files/$debug/" ]; then
                echo "processing files for $debug"
                while IFS= read -r -d $'' file; do
                    j2 "$file" > "$version/$variant/$debug/$(basename $file)"
                done < <(find files/$debug -maxdepth 1 -type f  -print0)
            fi

            dockerfiles+=( "$version/$variant/$debug/Dockerfile" )
            echo "  - {version: '$version', variant: '$variant', debug: '$debug', path: '$version/$variant/$debug'}" >> build.yml
        done
    done

    newTravisEnv=
    for dockerfile in "${dockerfiles[@]}"; do
        dir="${dockerfile%Dockerfile}"
        dir="${dir%/}"
        variant="${dir#$version}"
        variant="${variant#/}"
        newTravisEnv+='\n  - VERSION='"$version VARIANT=$variant"
    done
    travisEnv="$newTravisEnv$travisEnv"
    

done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml

#j2 files/templates/build.sh.j2 .travis.yml
