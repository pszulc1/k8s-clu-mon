/*
Other components

Usage:  
    jsonnet -J ../../vendor monitoring.jsonnet | jq 'keys'

Use the following command to obtain Prometheus Agent remoteWrite objects:

    jsonnet -J ../../vendor monitoring.jsonnet | jq '.["kube-prometheus"].prometheus.prometheusAgent.spec.remoteWrite'

Use the following commands to obtain all vector config files (ie. vector configuration) or the content of a specific one:

    jsonnet -J ../../vendor monitoring.jsonnet | jq '.vector.aggregator.configMap.data|keys'
    jsonnet -J ../../vendor monitoring.jsonnet | jq '.vector.aggregator.configMap.data["destination_logs.json"]' | jq 'fromjson'

*/

local kcm = import '../../main.libsonnet';
local config = import 'config.jsonnet';

(
  kcm.new(config.namespace, config.cluster, config.platform)
  + kcm.withMonitoredNamespacesMixin(['namespace-1', 'namespace-2'])
  + kcm.withPrometheusRemoteWriteMixin(
    [
      {
        name: 'prometheus-prod-instance',
        url: '...',
      },
    ]
  )
  + kcm.withVectorConfigsMixin(
    {
      'destination_logs.json': {    // redefines k8s-clu-mon's 'destination_logs.json' vector config file
        sinks: {
          'loki-prod-instance': {
            type: 'loki',
            inputs: ['k8s-clu-mon_logs'],  // output transform from k8s-clu-mon
            endpoint: '...',
            encoding: {
              codec: 'json',
            },
            labels: {
              '*': '{{%"k8s-clu-mon".labels}}',  // all k8s-clu-mon labels
            },
          },
        },
      },
    }
  )
).monitoring
