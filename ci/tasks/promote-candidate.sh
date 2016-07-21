#!/usr/bin/env bash

set -e

source bosh-cpi-src/ci/tasks/utils.sh
source /etc/profile.d/chruby-with-ruby-2.1.2.sh

check_param release_blobs_access_key
check_param release_blobs_secret_key

# Version info
semver_version=`cat release-version-semver/number`
integer_version=`cut -d "." -f1 release-version-semver/number`

# CPI vars
cpi_release_name="bosh-google-cpi"
cpi_blob=${cpi_release_name}-${integer_version}.tgz 
cpi_link=https://storage.googleapis.com/bosh-cpi-artifacts/bosh-google-cpi-$integer_version.tgz

# Stemcell vars
stemcell_path=$(basename `ls stemcell/*.tgz`)
stemcell_name=${stemcell_path%.*}
stemcell_version=`cat stemcell/version`
stemcell_url=`cat stemcell/url | sed "s|gs://|https://storage.googleapis.com/|"`
stemcell_type=Heavy
if [[ $stemcell_name == light* ]]; then stemcell_type=Light; fi

today=$(date +%Y-%m-%d)

echo $integer_version > promoted/integer_version
echo "BOSH Google CPI BOSH Release v${integer_version}" > promoted/annotation_message

cp -r bosh-cpi-src promoted/repo

dev_release=$(echo $PWD/bosh-cpi-release/*.tgz)

pushd promoted/repo
  echo "Creating config/private.yml with blobstore secrets"
  set +x
  cat > config/private.yml << EOF
---
blobstore:
  s3:
    access_key_id: ${release_blobs_access_key}
    secret_access_key: ${release_blobs_secret_key}
EOF

  echo "Using BOSH CLI version..."
  bosh version

  echo "Finalizing CPI BOSH Release..."
  bosh finalize release ${dev_release} --version ${integer_version}

  rm config/private.yml

  # Insert CPI details into README.md
  # Template markers in the README
  cpi_marker="\[//\]: # (new-cpi)"
  cpi_sha=$(sha1sum releases/$cpi_release_name/$cpi_blob | awk '{print $1}')
  new_cpi="|[$semver_version]($cpi_link)|$cpi_sha|$today|"
  sed -i "s^$cpi_marker^$new_cpi\n$cpi_marker^" README.md

  # Insert Stemcell details into README.md
  stemcell_marker="\[//\]: # (new-stemcell)"
  stemcell_sha=$(sha1sum stemcell/*.tgz | awk '{print $1}')
  new_stemcell="|[$stemcell_version ($stemcell_type)]($stemcell_url)|$stemcell_sha|$today|"
  sed -i "s^$stemcell_marker^$new_stemcell\n$stemcell_marker^" README.md

  git diff | cat
  git add .

  git config --global user.email cf-bosh-eng@pivotal.io
  git config --global user.name CI
  git commit -m "BOSH Google CPI BOSH Release v${integer_version}"

  mv releases/$cpi_release_name/$cpi_blob ../
  echo $cpi_sha > ../$cpi_blob.sha1
popd

