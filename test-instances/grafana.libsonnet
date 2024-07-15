/*
Grafana instance to analyze data from loki and prometheus test instances.
Following: https://grafana.com/docs/grafana/latest/setup-grafana/installation/kubernetes/?pg=oss-graf&plcmt=hero-btn-2

It is not monitored ie. the apropriate ServiceMonitor is not defined.

Consider using Grafana Operator via Jsonnet library?
*/

local k = import '../k.libsonnet';

local pvc = k.core.v1.persistentVolumeClaim;
local containerPort = k.core.v1.containerPort;
local servicePort = k.core.v1.servicePort;
local container = k.core.v1.container;
local deployment = k.apps.v1.deployment;
local service = k.core.v1.service;

local debug = (import '../debug.libsonnet')(std.thisFile, (import '../global.json').debug);


function(namespace, commonLabels)
  {
    local base = self,

    config:: {
      local this = self,

      namespace: namespace,

      name: 'grafana',
      component: 'analyzer',
      version: 'latest',
      image: 'grafana/grafana:' + this.version,

      labels:
        {
          'app.kubernetes.io/name': this.name,
          'app.kubernetes.io/component': this.component,
        }
        + commonLabels,
    },

    pvc:
      pvc.new(base.config.name + '-pvc')
      + pvc.metadata.withNamespace(base.config.namespace)
      + pvc.metadata.withLabels(base.config.labels)
      + pvc.spec.withAccessModes('ReadWriteOnce')
      + pvc.spec.resources.withRequests({ storage: '1Gi' })
    ,

    ports:: {
      http: {
        containerPort:
          containerPort.newNamed(name='http', containerPort=3000)
          + containerPort.withProtocol('TCP')
        ,
        servicePort:
          servicePort.newNamed(name='http', port=3000, targetPort=self.containerPort.containerPort)
          + servicePort.withProtocol(self.containerPort.protocol)
        ,
      },
    },

    container::
      container.new(base.config.name, base.config.image)
      + container.withImagePullPolicy('IfNotPresent')
      + container.withPorts([base.ports.http.containerPort])
      + container.resources.withRequests({ cpu: '250m', memory: '750Mi' })
    ,

    deployment:
      deployment.new(base.config.name, 1, [base.container])
      + deployment.metadata.withNamespace(base.config.namespace)
      + deployment.metadata.withLabels(base.config.labels)
      + deployment.spec.selector.withMatchLabels(base.config.labels)
      + deployment.spec.template.metadata.withLabels(base.config.labels)
      + deployment.spec.template.spec.securityContext.withFsGroup(472)
      + deployment.spec.template.spec.securityContext.withSupplementalGroups(0)
      + deployment.pvcVolumeMount(base.pvc.metadata.name, '/var/lib/grafana', containers=[base.container.name])
    ,

    service:
      service.new(
        base.config.name,
        base.deployment.spec.selector.matchLabels,
        [base.ports.http.servicePort]
      )
      + service.metadata.withNamespace(base.config.namespace)
      + service.metadata.withLabels(base.config.labels)
      + service.spec.withType('ClusterIP')
    ,

  }
  + {
    [if debug.on then '__debugMock']:
      debug.new('##0', $.config),
  }
