#!/bin/bash

set -e

if [[ -z "$PROJECT_ID" ]]; then
    echo "Must provide PROJECT_ID in environment" 1>&2
    exit 1
fi

echo "Setting project:"
gcloud config set project $PROJECT_ID

echo "Enabling GCP APIs (be patient):"
gcloud services enable \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    cloudresourcemanager.googleapis.com \
    compute.googleapis.com \
    iam.googleapis.com \
    run.googleapis.com \
    servicenetworking.googleapis.com \
    sqladmin.googleapis.com \
    vpcaccess.googleapis.com

echo "Creating service account:"
gcloud iam service-accounts create terraform

service_account_name="terraform@$PROJECT_ID.iam.gserviceaccount.com"

script_dir=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")

gcloud iam service-accounts keys create \
    "$script_dir/creds.json" \
    --iam-account $service_account_name

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:$service_account_name \
    --role roles/editor

# https://stackoverflow.com/a/61250654
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:$service_account_name \
    --role roles/run.admin

# https://serverfault.com/questions/942115
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:$service_account_name \
    --role roles/compute.networkAdmin

# https://stackoverflow.com/a/54351644
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:$service_account_name \
    --role roles/servicenetworking.serviceAgent
