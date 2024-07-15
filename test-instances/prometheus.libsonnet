/*
Prometheus instace collecting metrics from a prometheus agent.
For test purposes, e.g. to analyze scraped metrics before sending them to Grafana Cloud.

It is not monitored ie. the apropriate ServiceMonitor is not defined.
*/

local k = import '../k.libsonnet';

local containerPort = k.core.v1.containerPort;
local servicePort = k.core.v1.servicePort;
local container = k.core.v1.container;
local deployment = k.apps.v1.deployment;
local daemonSet = k.apps.v1.daemonSet;
local service = k.core.v1.service;
local configMap = k.core.v1.configMap;

local debug = (import '../debug.libsonnet')(std.thisFile, (import '../global.json').debug);


function(namespace, commonLabels)
  {
    local base = self,

    config:: {
      local this = self,

      namespace: namespace,

      name: 'prometheus',
      component: 'collector',
      version: 'latest',
      image: 'quay.io/prometheus/prometheus:' + this.version,

      labels:
        {
          'app.kubernetes.io/name': this.name,
          'app.kubernetes.io/component': this.component,
        }
        + commonLabels
      ,

      data_dir: '/etc/prometheus',
    },

    ports:: {
      web: {
        containerPort:
          containerPort.newNamed(name='web', containerPort=9090)
          + containerPort.withProtocol('TCP')
        ,
        servicePort:
          servicePort.newNamed(name='web', port=9090, targetPort=self.containerPort.containerPort)
          + servicePort.withProtocol(self.containerPort.protocol)
        ,
      },
    },

    container::
      container.new(base.config.name, base.config.image)
      + container.withArgs(
        [
          '--config.file',
          base.config.data_dir + '/' + base.promConfig.fileName,
          '--web.enable-remote-write-receiver',  // Remote Write Receiver
        ]
      )
      + container.withPorts([base.ports.web.containerPort])
    //+ container.resources.withRequests({ memory: '??', cpu: '??' })
    //+ container.resources.withLimits({ memory: '??', cpu: '??' })
    ,

    deployment:
      deployment.new(base.config.name, 1, [base.container])
      + deployment.metadata.withNamespace(base.config.namespace)
      + deployment.metadata.withLabels(base.config.labels)
      + deployment.spec.selector.withMatchLabels(base.config.labels)
      + daemonSet.spec.template.metadata.withLabels(base.config.labels)
      + deployment.configMapVolumeMount(base.configMap, base.config.data_dir, { readOnly: true }, containers=[base.container.name])
    ,

    service:
      service.new(
        base.config.name,
        base.deployment.spec.selector.matchLabels,
        [base.ports.web.servicePort]
      )
      + service.metadata.withNamespace(base.config.namespace)
      + service.metadata.withLabels(base.config.labels)
      + service.spec.withType('ClusterIP')
    ,

    promConfig:: {
      fileName: 'base.yaml',
      data:
        {
          global: {
            scrape_interval: '15s',
          },
          scrape_configs: [],
          rule_files: [],
        },
    },

    configMap:
      configMap.new(base.config.name)
      + configMap.metadata.withNamespace(base.config.namespace)
      + configMap.metadata.withLabels(base.config.labels)
      + configMap.withData(
        {
          [base.promConfig.fileName]: std.manifestYamlDoc(base.promConfig.data),
        }
      )
    ,

  }
  + {
    [if debug.on then '__debugMock']:
      {}
      + debug.new('##0', $.config)
      + debug.new('##1', $.promConfig),
  }
