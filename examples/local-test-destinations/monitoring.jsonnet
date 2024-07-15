/*
Other components

Usage:
    jsonnet -J ../.. -J ../../vendor monitoring.jsonnet | jq 'keys'

Use the following command to obtain Prometheus Agent remoteWrite objects:

    jsonnet -J ../.. -J ../../vendor monitoring.jsonnet | jq '.["kube-prometheus"].prometheus.prometheusAgent.spec.remoteWrite'

Use the following commands to obtain all vector config files (ie. vector configuration) or the content of a specific one:

    jsonnet -J ../.. -J ../../vendor monitoring.jsonnet | jq '.vector.aggregator.configMap.data|keys'
    jsonnet -J ../.. -J ../../vendor monitoring.jsonnet | jq '.vector.aggregator.configMap.data["destination_logs.json"]' | jq 'fromjson'

*/

local kcm = import '../../main.libsonnet';
local config = import 'config.jsonnet';


local testDestinations =
  (import '../../test-instances/destinations.libsonnet')
  + {
    loki+: {
      configs+: {
        'destination_logs.json'+: {

          transforms: {
            metadata_revealed: {
              type: 'remap',
              inputs: ['k8s-clu-mon_logs'],  // output transform from k8s-clu-mon
              source: |||
                .yyy_kubernetes_logs = %kubernetes_logs
                .yyy_vector = %vector
                ."yyy_k8s-clu-mon" = %"k8s-clu-mon"
              |||,
            },
          },

          sinks+: {
            'loki-test-instance'+: {
              inputs: ['metadata_revealed']  // input redefined
            }
          }

        },
      },
    },
  }
;


(
  kcm.new(config.namespace, config.cluster, config.platform)
  + kcm.withMonitoredNamespacesMixin(['this-namespace', 'that-namespace'])
  + kcm.withPrometheusRemoteWriteMixin([testDestinations.prometheus.remoteWrite])
  + kcm.withVectorConfigsMixin(testDestinations.loki.configs)  // redefines k8s-clu-mon's 'destination_logs.json' vector config file
).monitoring
