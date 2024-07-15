/*
Destinations to test instances.
*/

local loki = (import 'loki.libsonnet')('', {});
local prometheus = (import 'prometheus.libsonnet')('', {});

{

  prometheus: {
    name: 'prometheus-test-instance',
    remoteWrite: {
      name: $.prometheus.name,
      url:
        'http://'
        + prometheus.service.metadata.name
        + ':'
        + prometheus.service.spec.ports[0].port
        + '/api/v1/write',
    },
  },

  loki: {
    name: 'loki-test-instance',
    configs: {

      'destination_logs.json': {  // redefines k8s-clu-mon's 'destination_logs.json' vector config file
        sinks: {
          [$.loki.name]: {
            type: 'loki',
            // default name of the component that is the output for all k8s-clu-mon logs
            // should be changed if that name is modified
            inputs: ['k8s-clu-mon_logs'],
            endpoint: 'http://' + loki.write_service.metadata.name,
            path: '/loki/api/v1/push',
            out_of_order_action: 'accept',
            buffer: {
              type: 'disk',
              max_size: 536870912,  // 512 megabytes
            },
            encoding: {
              codec: 'json',
            },
            labels: {
              '*': '{{%"k8s-clu-mon".labels}}',  // all k8s-clu-mon labels
            },
          },
        },
      },

    },
  },

}
