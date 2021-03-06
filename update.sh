#!/usr/bin/env bash
set -Eeuo pipefail

versions=( */ )
versions=( "${versions[@]%/}" )

generated_warning() {
	cat <<-EOH
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#
	EOH
}

travisEnv=
for version in "${versions[@]}"; do
    if [[ "$version" == "files" ]]; then
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

    baseDockerfile=Dockerfile.template

    for variant in cli apache fpm; do
        [ -d "$version/$variant" ] || continue

        for debug in debug no-debug; do
            { generated_warning; cat "$baseDockerfile"; } > "$version/$variant/$debug/Dockerfile"

            echo "Generating $version/$variant/$debug/Dockerfile from $baseDockerfile + $variant-Dockerfile-block-*"
            gawk -i inplace -v variant="$variant" '
                $1 == "##</autogenerated>##" { ia = 0 }
                !ia { print }
                $1 == "##<autogenerated>##" { ia = 1; ab++; ac = 0; if (system("test -f " variant "-Dockerfile-block-" ab) != 0) { ia = 0 } }
                ia { ac++ }
                ia && ac == 1 { system("cat " variant "-Dockerfile-block-" ab) }
            ' "$version/$variant/$debug/Dockerfile"

            echo "Generating $version/$variant/$debug/Dockerfile from $baseDockerfile + $debug-Dockerfile-block-*"
            gawk -i inplace -v variant="$debug" '
                $1 == "##</debug>##" { ia = 0 }
                !ia { print }
                $1 == "##<debug>##" { ia = 1; ab++; ac = 0; if (system("test -f " variant "-Dockerfile-block-" ab) != 0) { ia = 0 } }
                ia { ac++ }
                ia && ac == 1 { system("cat " variant "-Dockerfile-block-" ab) }
            ' "$version/$variant/$debug/Dockerfile"

            if [ -d "files/$variant/" ]; then
              cp -rf "files/$variant/" $version/$variant/$debug
            fi

            if [ -d "files/$debug/" ]; then
              cp -rf "files/$debug/" $version/$variant/$debug
            fi

            # remove any _extra_ blank lines created by the deletions above
            awk '
                NF > 0 { blank = 0 }
                NF == 0 { ++blank }
                blank < 2 { print }
            ' "$version/$variant/$debug/Dockerfile" > "$version/$variant/$debug/Dockerfile.new"
            mv "$version/$variant/$debug/Dockerfile.new" "$version/$variant/$debug/Dockerfile"

            # automatic `-slim` for stretch
            # TODO always add slim once jessie is removed
            gsed -ri \
                -e 's!%%PHP_TAG%%!'"$version"'!' \
                -e 's!%%IMAGE_VARIANT%%!'"$variant"'!' \
                "$version/$variant/$debug/Dockerfile"
            dockerfiles+=( "$version/$variant/$debug/Dockerfile" )
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
