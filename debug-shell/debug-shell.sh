#!/usr/bin/env bash

IMAGE=${1:-centos:latest}

# This has been modified to work with the post 1.12 extended plugin model
# Also attach=true causes kubectl to not die out complaining about --rm
# in spite of the fact that -i is supposed to set attach=true?

kubectl run --attach=true -it --rm --restart=Never kube-shell --image ${IMAGE} -- bash
