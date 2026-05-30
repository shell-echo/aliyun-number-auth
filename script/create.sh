#!/usr/bin/env bash
set -euo pipefail

flutter upgrade && flutter doctor
flutter create \
    --template=plugin \
    --description "Aliyun phone number authentication Flutter plugin" \
    --org studio.echo \
    --project-name aliyun_number_auth \
    --platforms android,ios \
    --android-language kotlin \
    aliyun_number_auth
