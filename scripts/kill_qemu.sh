#!/usr/bin/env bash
# kill -9  $(ps aux | grep qemu | awk '//{print $2; exit}')
killall qemu-system-x86_64
