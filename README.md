# k8s-clu-mon

`k8s-clu-mon` is a jsonnet library that provides the minimal set of k8s components necessary to collect and forward metrics and logs to an external (outside cluster) destination. By design, storing, analysis and monitoring will take place outside the considered cluster.  
The resulting library is intended to be easy to use for monitoring subsequent clusters.  

The library uses [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus) with [Prometheus Agent](https://prometheus.io/blog/2021/11/16/agent/) and [Vector](https://vector.dev/) deployed as an agent and aggregator.  

## Quickstart

- [./docs](./docs/README.md) for more information
- `./examples` for basic usage
- [k8s-clu-mon-example](https://github.com/pszulc1/k8s-clu-mon-example) for more intricate working example 

## Initial project setup (and library versions used)

```sh
jb init

echo 'vendor/' >> .gitignore

# k8s-libsonnet version corresponding to the kube-prometheus version in use
jb install github.com/jsonnet-libs/k8s-libsonnet/1.28@main
# see kube-prometheus compatibility at https://github.com/prometheus-operator/kube-prometheus
jb install github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus@release-0.13
# corresponding to the version of Prometheus Operator (0.67.1) used in the chosen version of kube-prometheus 
jb install github.com/jsonnet-libs/prometheus-operator-libsonnet/0.67@main

# Loki SSD latest working version (3.0.0 doesn't work at the moment) and necessary library
jb install github.com/grafana/loki/production/ksonnet/loki-simple-scalable@v2.9.8
jb install github.com/grafana/jsonnet-libs/ksonnet-util

# latest version
jb install github.com/jsonnet-libs/docsonnet/doc-util@v0.0.5
# releases are not available
jb install github.com/jsonnet-libs/testonnet@master
```

## Development

Initial versions of the library were prepared on GKE for the [opalcbox.pl](https://www.opalcbox.pl/) application, which was deployed on the same platform. Subsequent versions of a library have been developed on [kind](https://kind.sigs.k8s.io/) and on this platform library has been tested.  

To analyse returned components check:  

```sh
jsonnet -J vendor test/experiments.jsonnet | jq 'keys'
```

To check values generated by debug messages set `(global.json).debug` to `true` and use (for example):

```sh
./d2j test/experiments.jsonnet main.libsonnet 0

./d2j test/experiments.jsonnet vector.libsonnet 22 | jq 'keys'
./d2j test/experiments.jsonnet vector.libsonnet 23
```

Search for `debug.new` in source files for other messages.  

`make docs` generates docs.  

`make test` runs tests.  
If necessary use `jsonnet -m test/base -J vendor test/base.jsonnet` to prepare `test/base/*` files.  
Test cases are not comprehensive, they should rather be treated as proof of concept.  

To close the new release:

- set `(import 'global.json').version` consistently with the new release tag,
- `make docs` to update reference to version tag which was set as above.

## Project status

It is the first version, although it has been revised many times needs tunning and extensions.  
Some directions of future works include:

- improving the security of communication between components, eg. in the same way as in the `kube-prometheus` package
- hardening Vector components following [Hardening Vector](https://vector.dev/docs/setup/going-to-prod/hardening/)
- better handling data processing failures in Vector components, eg. applying [reroute_dropped](https://vector.dev/docs/reference/configuration/transforms/remap/#reroute_dropped)  
- improving HA by autoscaling aggregators and/or adding pub-sub systems (see [Aggregator Architecture](https://vector.dev/docs/setup/going-to-prod/arch/aggregator/))
- applying `blackboxExporter` and `prometheusAdapter` from `kube-prometheus` package

The library should be updated as new versions of the libraries in use become available.  
