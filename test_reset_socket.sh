#!/bin/bash

source functions.sh
reset_socket
[ $? -eq 1 ] && { echo -e "NOK Socket not reset" ; exit 1; } || echo -e "OK Socket successfully reset"
echo "podman socket exported: MINIAPP_TRAEFIK_PODMAN_SOCK=$MINIAPP_TRAEFIK_PODMAN_SOCK"
echo -e ".bashrc: " && grep MINIAPP_TRAEFIK_PODMAN_SOCK $HOME/.bashrc