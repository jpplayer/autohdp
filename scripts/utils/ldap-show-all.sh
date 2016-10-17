#!/bin/bash

slapcat -n0
ldapsearch -x -b "dc=hadoop,dc=io"

