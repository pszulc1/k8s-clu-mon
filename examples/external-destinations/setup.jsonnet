/*
Setup to be deployed first.

Usage:  
    jsonnet -J ../../vendor setup.jsonnet | jq 'keys'

*/

local kcm = import '../../main.libsonnet';
local config = import 'config.jsonnet';

(kcm.new(config.namespace, config.cluster, config.platform)).setup
