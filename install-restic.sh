#!/bin/bash
apt-get update
apt-get install restic

cp .restic.env ~/.restic.env
source ~/.restic.env
