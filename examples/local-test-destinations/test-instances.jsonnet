/*
Local instances for test purposes.

Usage:
    jsonnet -J ../.. -J ../../vendor test-instances.jsonnet | jq 'keys'

To get final loki configuration:
    jsonnet -J ../.. -J ../../vendor test-instances.jsonnet \
    | jq '.["loki"].config_file.data["config.yaml"]' \
    | yq -P | yq -o json | jq

*/

{
  local config = import 'config.jsonnet',

  prometheus: (import '../../test-instances/prometheus.libsonnet')(config.namespace, {}),

  loki: (import '../../test-instances/loki.libsonnet')(config.namespace, {}),

  grafana: (import '../../test-instances/grafana.libsonnet')(config.namespace, {}),
}
