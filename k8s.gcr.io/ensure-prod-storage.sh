#!/usr/bin/env bash
#
# Copyright 2019 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script creates & configures the "real" serving repo in GCR,
# along with the prod GCS bucket.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "${SCRIPT_DIR}/lib.sh"

function usage() {
    echo "usage: $0" > /dev/stderr
    echo > /dev/stderr
}

if [ $# != 0 ]; then
    usage
    exit 1
fi

# The GCP project names.
TEST_PROJECT="k8s-cip-test-prod"
PROD_PROJECT="k8s-artifacts-prod"
TRASH_PROJECT="k8s-artifacts-graveyard"

ALL_PROJECTS=("${TEST_PROJECT}" "${PROD_PROJECT}" "${TRASH_PROJECT}")

# GCS bucket for prod
PROD_BUCKET=gs://k8s-artifacts-prod

# Regions for prod.
PROD_REGIONS=(us eu asia)

# Make the projects, if needed
for prj in "${ALL_PROJECTS[@]}"; do
    color 6 "Ensuring project exists: ${prj}"
    ensure_project "${prj}"

    color 6 "Configuring billing: ${prj}"
    ensure_billing "${prj}"

    color 6 "Enabling the container registry API: ${prj}"
    enable_api "${prj}" containerregistry.googleapis.com

    color 6 "Enabling the container analysis API for: ${prj}"
    enable_api "${prj}" containeranalysis.googleapis.com

    color 6 "Ensuring the registry exists and is readable: ${prj}"
    for r in "${PROD_REGIONS[@]}"; do
        color 3 "region $r"
        ensure_repo "${prj}" "${r}"
    done

    color 6 "Empowering GCR admins: ${prj}"
    for r in "${PROD_REGIONS[@]}"; do
        color 3 "region $r"
        empower_gcr_admins "${prj}" "${r}"
    done

    color 6 "Empowering image promoter to GCR: ${prj}"
    for r in "${PROD_REGIONS[@]}"; do
        color 3 "region $r"
        empower_promoter "${prj}" "${r}"
    done
done

# Special cases
color 6 "Empowering cip-test group in cip-test for GCR"
for r in "${PROD_REGIONS[@]}"; do
    color 3 "region $r"
    empower_group_to_repo "${TEST_PROJECT}" "k8s-infra-gcr-staging-cip-test@googlegroups.com" "${r}"
done

# Create bucket
color 6 "Creating GCS bucket ${PROD_BUCKET} in ${PROD_PROJECT}"

# Enable GCS APIs
color 6 "Enabling the GCS API"
enable_api "${PROD_PROJECT}" storage-component.googleapis.com

# Create the GCS bucket (in the US multi-regional location)
color 6 "Ensuring the bucket exists and is world readable"
ensure_gcs_bucket "${PROD_PROJECT}" "${PROD_BUCKET}"

# Enable admins on the bucket
color 6 "Empowering GCS admins"
empower_gcs_admins "${PROD_PROJECT}" "${PROD_BUCKET}"

color 6 "Done"
