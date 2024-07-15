local test = import '../vendor/testonnet/main.libsonnet';

local params = {

  namespace: 'my-namespace',
  cluster: 'my-cluster',

  monitoredNamespaces: ['namespace-1', 'namespace-2'],

  'kube-prometheus'+: {
    platform: 'platform-77',
    remoteWrite+: [
      {
        name: 'rw-1',
        url: 'https://aa.com',
      },
      {
        name: 'rw-2',
        url: 'https://aa.com',
        writeRelabelConfigs: [
          {
            sourceLabels: ['some-label', '__name__'],
            regex: 'some_label_value;metric_name',
            action: 'drop',
          },
        ],
      },
    ],
  },

  vector: {},

};


local global = import '../global.json';
local kcm = import '../main.libsonnet';

local versionLabelsMixin = {
  metadata+: {
    labels+: { 'app.kubernetes.io/version': global.version },
  },
};


local eqJson = test.expect.new(
  function(actual, expected) actual == expected,
  function(actual, expected)
    '\n---Actual---------------------------------------------------------------------------------------\n'
    + std.manifestJson(actual)
    + '\n---Expected-------------------------------------------------------------------------------------\n'
    + std.manifestJson(expected),
);


local defaultServiceMonitor = import 'base/default-service-monitor.json';
local prometheusAgent = import 'test/base/prometheus-agent.json';


test.new(std.thisFile)

+ test.case.new(
  'namespace',
  eqJson(
    (kcm.new(params.namespace, params.cluster)).setup.namespace
    ,
    (import 'base/namespace.json') + versionLabelsMixin
  )
)
+ test.case.new(
  'defaultServiceMonitor + .spec.namespaceSelector / .withMonitoredNamespacesMixin()',
  eqJson(
    (
      kcm.new(params.namespace, params.cluster)
      + kcm.withMonitoredNamespacesMixin(params.monitoredNamespaces)
    ).monitoring.defaultServiceMonitor
    ,
    defaultServiceMonitor + versionLabelsMixin
    + {
      spec+: {
        namespaceSelector: {
          matchNames: params.monitoredNamespaces,
        },
      },
    }
  )
)

+ test.case.new(
  '.setup["kube-prometheus"] content',
  eqJson(
    std.objectFields((kcm.new(params.namespace, params.cluster)).setup['kube-prometheus'])
    ,
    ['prometheusOperator']
  )
)
+ test.case.new(
  '.setup["kube-prometheus"].prometheusOperator content',
  eqJson(
    std.objectFields((kcm.new(params.namespace, params.cluster)).setup['kube-prometheus'].prometheusOperator)
    ,
    (import 'test/base/setup-kp-po-contents.json')
  )
)

+ test.case.new(
  '.monitoring["kube-prometheus"] content',
  eqJson(
    std.objectFields((kcm.new(params.namespace, params.cluster)).monitoring['kube-prometheus'])
    ,
    (import 'test/base/main-kp-contents.json')
  )
)
+ test.case.new(
  '.monitoring["kube-prometheus"].prometheusOperator content',
  eqJson(
    std.objectFields((kcm.new(params.namespace, params.cluster)).monitoring['kube-prometheus'].prometheusOperator)
    ,
    ['serviceMonitor']
  )
)

+ test.case.new(
  '.monitoring["kube-prometheus"].prometheus content',
  eqJson(
    std.objectFields((kcm.new(params.namespace, params.cluster)).monitoring['kube-prometheus'].prometheus)
    ,
    (import 'test/base/main-kp-po-contents.json')
  )
)


+ test.case.new(
  'prometheusAgent',
  eqJson(
    (kcm.new(params.namespace, params.cluster)).monitoring['kube-prometheus'].prometheus.prometheusAgent
    ,
    prometheusAgent
    + {
      spec+: {
        externalLabels+: {'k8s_clu_mon_version': global.version}
      }
    }
  )
)
+ test.case.new(
  'prometheusAgent + .spec.remoteWrite / .withPrometheusRemoteWriteMixin()',
  eqJson(
    (
      kcm.new(params.namespace, params.cluster)
      + kcm.withPrometheusRemoteWriteMixin([params['kube-prometheus'].remoteWrite[0]])
    ).monitoring['kube-prometheus'].prometheus.prometheusAgent
    ,
    prometheusAgent
    {
      spec+: {
        externalLabels+: {'k8s_clu_mon_version': global.version},
        remoteWrite: [params['kube-prometheus'].remoteWrite[0]],
      },
    }
  )
)
+ test.case.new(
  'prometheusAgent + .spec.remoteWrite / .withPrometheusRemoteWriteMixin() + remoteWrite with writeRelabelConfigs',
  eqJson(
    (
      kcm.new(params.namespace, params.cluster)
      + kcm.withPrometheusRemoteWriteMixin([params['kube-prometheus'].remoteWrite[1]])
    ).monitoring['kube-prometheus'].prometheus.prometheusAgent
    ,
    prometheusAgent
    {
      spec+: {
        externalLabels+: {'k8s_clu_mon_version': global.version},
        remoteWrite: [params['kube-prometheus'].remoteWrite[1]],
      },
    }
  )
)
+ test.case.new(
  'prometheusAgent + MANY .spec.remoteWrite / .withPrometheusRemoteWriteMixin() + remoteWrite with writeRelabelConfigs',
  eqJson(
    (
      kcm.new(params.namespace, params.cluster)
      + kcm.withPrometheusRemoteWriteMixin(
        [params['kube-prometheus'].remoteWrite[1]] + [params['kube-prometheus'].remoteWrite[0]]
      )
    ).monitoring['kube-prometheus'].prometheus.prometheusAgent
    ,
    prometheusAgent
    {
      spec+: {
        externalLabels+: {'k8s_clu_mon_version': global.version},
        remoteWrite: [
          params['kube-prometheus'].remoteWrite[1],
          params['kube-prometheus'].remoteWrite[0],
        ],
      },
    }
  )
)
