/*
Definitions based on https://github.com/vectordotdev/vector/tree/v0.36.1/distribution/kubernetes

I do not use [Vector Operator](https://github.com/kaasops/vector-operator) as it doesn't support aggregator role and
there is no jsonnet library to use it.
*/

local k = import 'k.libsonnet';

local clusterRole = k.rbac.v1.clusterRole;
local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
local subject = k.rbac.v1.subject;
local policyRule = k.rbac.v1.policyRule;
local serviceAccount = k.core.v1.serviceAccount;

local containerPort = k.core.v1.containerPort;
local servicePort = k.core.v1.servicePort;
local container = k.core.v1.container;
local envFromSource = k.core.v1.envFromSource;
local envVar = k.core.v1.envVar;
local daemonSet = k.apps.v1.daemonSet;
local deployment = k.apps.v1.deployment;
local service = k.core.v1.service;
local configMap = k.core.v1.configMap;

local serviceMonitor = (import 'po.libsonnet').monitoring.v1.serviceMonitor;

local debug = (import 'debug.libsonnet')(std.thisFile, (import 'global.json').debug);

local utils = import 'utils.libsonnet';


local objDefArray(key, value) =
  // key may not be empty, value can be of any type except the function
  // string values must be quoted accordingly eg. '"aaa-bbb-ccc"'
  if !std.isObject(value) then ['"' + key + '"=' + value]
  else
    std.flattenArrays(
      [
        std.map(
          function(x) '"' + key + '".' + x,
          objDefArray(field, value[field])
        )
        for field in std.objectFields(value)
      ]
    )
;

local objPathValueArray(array) =
  // array must be defined the same as output from objDefArray()
  [
    std.split(_elem, '=')
    for _elem in array
  ]
;


function(params)

  local config =
    {
      namespace: error 'must provide namespace',
      name: error 'must provide name',

      commonLabels: {},
      promotedPodLabels: [],
      externalLabels: {},

      monitoredNamespaces: [],

      vector: {
        apiPort: error 'must provide api port',
        metricsPort: error 'must provide metrics port',
        configs: {},
        envFromSecretRefs: [],

        version: '0.35.0-distroless-libc',  // use *-alpine for `kubectl exec -it`
        image: 'timberio/vector:' + self.version,
        configDir: '/etc/vector/',
        dataDir: '/vector-data-dir',
        containerName: 'vector',
      },
    }
    + params
  ;

  {
    agent:
      {
        local agent = self,

        config::
          config
          {
            vector+: {
              name: 'vector-agent',
              component: 'agent',

              logDir: '/var/log/',
              libDir: '/var/lib',
              procDir: '/host/proc',
              sysDir: '/host/sys',
            },

            commonLabels+: {
              'app.kubernetes.io/name': agent.config.vector.name,
              'app.kubernetes.io/component': agent.config.vector.component,
            },
          }
        ,

        clusterRole:
          clusterRole.new(agent.config.vector.name)
          + clusterRole.metadata.withNamespace(agent.config.namespace)
          + clusterRole.metadata.withLabels(agent.config.commonLabels)
          + clusterRole.withRules(
            [
              policyRule.withApiGroups('')
              + policyRule.withResources(['namespaces', 'nodes', 'pods'])
              + policyRule.withVerbs(['list', 'watch']),
            ]
          )
        ,

        clusterRoleBinding:
          clusterRoleBinding.new(agent.config.vector.name)
          + clusterRoleBinding.metadata.withNamespace(agent.config.namespace)
          + clusterRoleBinding.metadata.withLabels(agent.config.commonLabels)
          + clusterRoleBinding.bindRole(agent.clusterRole)
          + clusterRoleBinding.withSubjects([subject.fromServiceAccount(agent.serviceAccount)])
        ,

        serviceAccount:
          serviceAccount.new(agent.config.vector.name)
          + serviceAccount.withAutomountServiceAccountToken(true)
          + serviceAccount.metadata.withNamespace(agent.config.namespace)
          + serviceAccount.metadata.withLabels(agent.config.commonLabels)
        ,

        ports:: {
          api: {
            containerPort:
              containerPort.newNamed(name='api', containerPort=agent.config.vector.apiPort)
              + containerPort.withProtocol('TCP')
            ,
            servicePort: {},
          },
          metrics: {
            containerPort:
              containerPort.newNamed(name='metrics', containerPort=agent.config.vector.metricsPort)
              + containerPort.withProtocol('TCP')
            ,
            servicePort:
              servicePort.newNamed(name='metrics', port=agent.config.vector.metricsPort, targetPort=self.containerPort.containerPort)
              + servicePort.withProtocol(self.containerPort.protocol),
          },
        },

        containers:: {
          vector:
            container.new(name=agent.config.vector.containerName, image=agent.config.vector.image)
            + container.withImagePullPolicy('IfNotPresent')
            + container.withEnv(
              [
                envVar.new('VECTOR_CONFIG_DIR', agent.config.vector.configDir),
                envVar.new('VECTOR_REQUIRE_HEALTHY', 'true'),  // crucial!
                envVar.new('PROCFS_ROOT', agent.config.vector.procDir),
                envVar.new('SYSFS_ROOT', agent.config.vector.sysDir),
                envVar.new('VECTOR_LOG', 'info'),
                envVar.new('VECTOR_LOG_FORMAT', 'json'),
                envVar.fromFieldPath('VECTOR_SELF_NODE_NAME', 'spec.nodeName'),
                envVar.fromFieldPath('VECTOR_SELF_POD_NAME', 'metadata.name'),
                envVar.fromFieldPath('VECTOR_SELF_POD_NAMESPACE', 'metadata.namespace'),
              ]
            )
            + container.withPorts(
              [
                agent.ports[_port].containerPort
                for _port in std.objectFields(agent.ports)
              ]
            )
            // following https://vector.dev/docs/reference/configuration/sources/kubernetes_logs/#resource-limits
            // & https://vector.dev/docs/setup/going-to-prod/arch/agent/#sizing-scaling--capacity-planning
            + container.resources.withRequests({ memory: '64Mi', cpu: '500m' })
            + container.resources.withLimits({ memory: '1024Mi', cpu: '6000m' }),
        },

        daemonset:
          daemonSet.new(agent.config.vector.name, [agent.containers.vector])
          + daemonSet.metadata.withNamespace(agent.config.namespace)
          + daemonSet.metadata.withLabels(agent.config.commonLabels)
          + daemonSet.spec.selector.withMatchLabels(agent.config.commonLabels { 'app.kubernetes.io/version':: '' })
          + daemonSet.spec.withMinReadySeconds(0)
          + daemonSet.spec.template.metadata.withLabels(agent.config.commonLabels)
          + daemonSet.spec.template.metadata.withAnnotations({ 'kubectl.kubernetes.io/default-container': agent.containers.vector.name })
          + daemonSet.spec.template.spec.withServiceAccountName(agent.serviceAccount.metadata.name)
          + daemonSet.spec.template.spec.withTerminationGracePeriodSeconds(60)
          + daemonSet.spec.template.spec.withDnsPolicy('ClusterFirst')
          + daemonSet.configMapVolumeMount(agent.configMap, agent.config.vector.configDir, { readOnly: true }, containers=[agent.containers.vector.name])
          + daemonSet.hostVolumeMount('data-volume', '/var/lib/vector', agent.config.vector.dataDir, containers=[agent.containers.vector.name])
          + daemonSet.hostVolumeMount('log-volume', '/var/log/', agent.config.vector.logDir, true, containers=[agent.containers.vector.name])
          + daemonSet.hostVolumeMount('lib-volume', '/var/lib/', agent.config.vector.libDir, true, containers=[agent.containers.vector.name])
          + daemonSet.hostVolumeMount('procfs-volume', '/proc', agent.config.vector.procDir, true, containers=[agent.containers.vector.name])
          + daemonSet.hostVolumeMount('sysfs-volume', '/sys', agent.config.vector.sysDir, true, containers=[agent.containers.vector.name])
        ,

        service:
          service.new(
            agent.config.vector.name,
            agent.daemonset.spec.selector.matchLabels,
            [agent.ports.metrics.servicePort]
          )
          + service.metadata.withNamespace(agent.config.namespace)
          + service.metadata.withLabels(agent.config.commonLabels)
          + service.spec.withClusterIP('None')
          + service.spec.withType('ClusterIP')
        ,

        serviceMonitor:
          serviceMonitor.new(agent.config.vector.name)
          + serviceMonitor.metadata.withNamespace(agent.config.namespace)
          + serviceMonitor.metadata.withLabels(agent.config.commonLabels)
          + serviceMonitor.spec.withJobLabel('app.kubernetes.io/name')
          + serviceMonitor.spec.withEndpoints(
            [
              {
                interval: '30s',
                port: 'metrics',
              },
            ]
          )
          + serviceMonitor.spec.selector.withMatchLabels(agent.service.metadata.labels)
        ,

        configs:: {
          'base.json': {
            data_dir: agent.config.vector.dataDir,
            api: {
              enabled: true,
              address: '127.0.0.1:' + agent.config.vector.apiPort,
              playground: false,
            },
            schema: {
              log_namespace: true,  // see https://vector.dev/blog/log-namespacing/
            },

            sources: {
              internal_metrics: {
                type: 'internal_metrics',
                namespace: 'vector',
              },
              kubernetes_logs: {
                type: 'kubernetes_logs',
              },
            },

            transforms: {
              monitored_namespaces_filtered: {
                local _logNamespaces =
                  std.set(
                    ['default', 'kube-system', agent.config.namespace]  // namespaces monitored by default
                    + agent.config.monitoredNamespaces
                  ),  // duplication excluded
                type: 'filter',
                inputs: ['kubernetes_logs'],
                condition:
                  std.foldl(
                    function(result, elem) result + elem,
                    [
                      '%kubernetes_logs.pod_namespace=='
                      + '"'
                      + _logNamespaces[_index]
                      + '"'
                      + if _index != (std.length(_logNamespaces) - 1) then ' || ' else ''
                      for _index in std.makeArray(std.length(_logNamespaces), function(i) i)
                    ],
                    ''
                  ),
              },
            },

            sinks: {
              prometheus_exporter: {
                type: 'prometheus_exporter',
                inputs: ['internal_metrics'],
                address: '0.0.0.0:' + agent.config.vector.metricsPort,
                flush_period_secs: 60,  // higher than agent.serviceMonitor scrape interval
              },

              'vector-aggregator': {
                type: 'vector',
                inputs: ['monitored_namespaces_filtered'],
                address:
                  'http://'
                  + $.aggregator.service.metadata.name
                  + ':'
                  + $.aggregator.ports.sink.servicePort.port,
                compression: true,
                request: {
                  timeout_secs: 120,  // default is 60
                },
              },
            },
          },
        },

        configMap:
          configMap.new(agent.config.vector.name)
          + configMap.metadata.withNamespace(agent.config.namespace)
          + configMap.metadata.withLabels(agent.config.commonLabels)
          + configMap.withData(
            {
              [_config]: std.manifestJsonEx(agent.configs[_config], '  ')
              for _config in std.objectFields(agent.configs)
            }
          )
        ,

        networkPolicy:: {},  // todo
        podDisruptionBudget:: {},  // todo

      }
      + {
        [if debug.on then '__debugMock']:
          {}
          + debug.new('##0', config)
          + debug.new('##11', $.agent.config)
          + debug.new('##12', $.agent.configs),
      }
    ,

    aggregator:
      {
        local aggregator = self,

        config::
          config
          {
            vector+: {
              name: 'vector-aggregator',
              component: 'aggregator',
            },

            commonLabels+: {
              'app.kubernetes.io/name': aggregator.config.vector.name,
              'app.kubernetes.io/component': aggregator.config.vector.component,
            },
          },

        serviceAccount:
          serviceAccount.new(aggregator.config.vector.name)
          + serviceAccount.withAutomountServiceAccountToken(true)
          + serviceAccount.metadata.withNamespace(aggregator.config.namespace)
          + serviceAccount.metadata.withLabels(aggregator.config.commonLabels)
        ,

        ports:: {
          api: {
            containerPort:
              containerPort.newNamed(name='api', containerPort=aggregator.config.vector.apiPort)
              + containerPort.withProtocol('TCP')
            ,
            servicePort:
              servicePort.newNamed(name='api', port=aggregator.config.vector.apiPort, targetPort=self.containerPort.containerPort)
              + servicePort.withProtocol(self.containerPort.protocol),
          },
          metrics: {
            containerPort:
              containerPort.newNamed(name='metrics', containerPort=aggregator.config.vector.metricsPort)
              + containerPort.withProtocol('TCP')
            ,
            servicePort:
              servicePort.newNamed(name='metrics', port=aggregator.config.vector.metricsPort, targetPort=self.containerPort.containerPort)
              + servicePort.withProtocol(self.containerPort.protocol),
          },
          sink: {
            containerPort:
              containerPort.newNamed(name='sink', containerPort=6000)
              + containerPort.withProtocol('TCP')
            ,
            servicePort:
              servicePort.newNamed(name='sink', port=6000, targetPort=self.containerPort.containerPort)
              + servicePort.withProtocol(self.containerPort.protocol),
          },
        },

        containers:: {
          vector:
            container.new(name=aggregator.config.vector.containerName, image=aggregator.config.vector.image)
            + container.withImagePullPolicy('IfNotPresent')
            + container.withEnv(
              [
                envVar.new('VECTOR_CONFIG_DIR', aggregator.config.vector.configDir),
                envVar.new('VECTOR_LOG', 'info'),
                envVar.new('VECTOR_LOG_FORMAT', 'json'),
              ]
            )
            + container.withPorts(
              [
                aggregator.ports[_port].containerPort
                for _port in std.objectFields(aggregator.ports)
              ]
            )
            // following https://vector.dev/docs/reference/configuration/sources/kubernetes_logs/#resource-limits
            // && https://vector.dev/docs/setup/going-to-prod/arch/aggregator/#sizing-scaling--capacity-planning
            + container.resources.withRequests({ memory: '64Mi', cpu: '500m' })
            + container.resources.withLimits({ memory: '4096Mi', cpu: '6000m' })
            + container.withEnvFromMixin(
              [
                envFromSource.secretRef.withName(_secretName)
                for _secretName in aggregator.config.vector.envFromSecretRefs
              ]
            ),
        },

        deployment:
          deployment.new(aggregator.config.vector.name, replicas=1, containers=[aggregator.containers.vector])
          + deployment.metadata.withNamespace(aggregator.config.namespace)
          + deployment.metadata.withLabels(aggregator.config.commonLabels)

          + deployment.spec.selector.withMatchLabels(aggregator.config.commonLabels { 'app.kubernetes.io/version':: '' })
          + deployment.spec.template.metadata.withLabels(aggregator.config.commonLabels)
          + deployment.spec.template.metadata.withAnnotations({ 'kubectl.kubernetes.io/default-container': aggregator.containers.vector.name })
          + deployment.spec.template.spec.withDnsPolicy('ClusterFirst')
          + deployment.spec.template.spec.withTerminationGracePeriodSeconds(60)
          + deployment.spec.template.spec.withServiceAccountName(aggregator.serviceAccount.metadata.name)
          + deployment.configMapVolumeMount(aggregator.configMap, aggregator.config.vector.configDir, { readOnly: true }, containers=[aggregator.containers.vector.name])
          + deployment.emptyVolumeMount('data-volume', aggregator.config.vector.dataDir, containers=[aggregator.containers.vector.name])
        ,

        service:
          service.new(
            aggregator.config.vector.name,
            aggregator.deployment.spec.selector.matchLabels,
            [
              aggregator.ports[_port].servicePort
              for _port in std.objectFields(aggregator.ports)
            ]
          )
          + service.metadata.withNamespace(aggregator.config.namespace)
          + service.metadata.withLabels(aggregator.config.commonLabels)
          + service.spec.withType('ClusterIP')
        ,

        serviceMonitor:
          serviceMonitor.new(aggregator.config.vector.name)
          + serviceMonitor.metadata.withNamespace(aggregator.config.namespace)
          + serviceMonitor.metadata.withLabels(aggregator.config.commonLabels)
          + serviceMonitor.spec.withJobLabel('app.kubernetes.io/name')
          + serviceMonitor.spec.withEndpoints(
            [
              {
                interval: '30s',
                port: 'metrics',
              },
            ]
          )
          + serviceMonitor.spec.selector.withMatchLabels(aggregator.service.metadata.labels)
        ,

        customMetadata:: {
          // k8s-clu-mon vector's events metadata
          // values can be of any type except the function
          // string values must be quoted accordingly eg. '"aaa-bbb-ccc"'
          // nullish values (in VRL meaning) doesn't make sense - this means the field is not defined
          // although they may be defined, such fields are later removed
          // if a field is to be used as a loki stream label:
          //  its name must comply with the same restrictions as metric label name see: https://prometheus.io/docs/concepts/data_model/#metric-names-and-labels
          //  its value must not be an array, not only it is pointless, but causes non-obvious label setting and sink log ingestion errors

          // a set of loki stream labels
          // label names comply with the same restrictions as metric label name
          labels:
            // the same set as for metrics label name:
            {
              [label]: '"' + config.externalLabels[label] + '"'
              for label in std.objectFields(config.externalLabels)
            }
            + {
              namespace: '%kubernetes_logs.pod_namespace',
              container: '%kubernetes_logs.container_name',
            }
            + {
              [utils.metricLabelName(label)]: '%kubernetes_logs.pod_labels.' + '"' + label + '"'
              for label in config.promotedPodLabels
            }
            // plus some other:
            + {
              node: '%kubernetes_logs.pod_node_name',
            }
          ,
        },

        configs::
          {
            'base.json': {
              data_dir: aggregator.config.vector.dataDir,
              api: {
                enabled: true,
                address: '127.0.0.1:' + aggregator.config.vector.apiPort,
                playground: false,
              },
              schema: {
                log_namespace: true,  // see https://vector.dev/blog/log-namespacing/
              },

              sources: {
                internal_metrics: {
                  type: 'internal_metrics',
                  namespace: 'vector',
                },
                kubernetes_logs: {
                  type: 'vector',
                  address: '0.0.0.0:' + aggregator.ports.sink.containerPort.containerPort,
                  version: '2',
                },
              },

              local baseRouted = 'base_routed',
              local baseConverted = baseRouted + '_',
              transforms: {

                local customMetadataDefArray =
                  [
                    '%' + _elem
                    for _elem in objDefArray(aggregator.config.name, aggregator.customMetadata)
                  ],

                custom_metadata_added:
                  {
                    type: 'remap',
                    inputs: ['kubernetes_logs'],
                    source:
                      '\n' +
                      std.foldl(
                        function(result, elem) result + elem + '\n',
                        customMetadataDefArray,
                        ''
                      ),
                  }
                  + debug.new('##31', customMetadataDefArray)
                ,

                custom_metadata_nullish_removed:
                  {
                    type: 'remap',
                    inputs: ['custom_metadata_added'],
                    source:
                      '\n' +
                      std.foldl(
                        function(result, elem) result + elem + '\n',
                        [
                          'if is_nullish(' + _elem[0] + ') { del(' + _elem[0] + ') }'
                          for _elem in objPathValueArray(customMetadataDefArray)
                        ],
                        ''
                      ),
                  }
                  + debug.new('##32', objPathValueArray(customMetadataDefArray))
                ,

                // payload translation to JSON for a substantial container logs
                [baseRouted]:
                  {
                    type: 'route',
                    inputs: ['custom_metadata_nullish_removed'],
                    reroute_unmatched: true,
                    route: {
                      prometheus:
                        '%kubernetes_logs.pod_namespace == ' + '"' + aggregator.config.namespace + '"'  // the same as Prometheus
                        + '&& ('
                        + '%kubernetes_logs.container_name == "prometheus"'
                        + '||'
                        + '%kubernetes_logs.container_name == "config-reloader"'
                        + '||'
                        + '%kubernetes_logs.container_name == "prometheus-operator"'
                        + ')'
                      ,
                      vector:
                        '%kubernetes_logs.pod_namespace == ' + '"' + aggregator.config.namespace + '"'  // the same for aggregator and agent
                        + '&&'
                        + '%kubernetes_logs.container_name == ' + '"' + aggregator.config.vector.containerName + '"'  // the same for aggregator and agent
                      ,
                    },
                  }
                ,
                [baseConverted + 'prometheus']:
                  {
                    type: 'remap',
                    inputs: [baseRouted + '.prometheus'],
                    source: '. = parse_logfmt!(.)',
                  }
                ,
                [baseConverted + 'vector']:
                  {
                    type: 'remap',
                    inputs: [baseRouted + '.vector'],
                    source: '. = parse_json!(.)',
                  }
                ,
                [baseConverted + 'unmatched']:
                  {
                    type: 'remap',
                    inputs: [baseRouted + '._unmatched'],
                    source: '.payload=.',
                  }
                ,

                // final aggregator's transform for all logs (output for all aggregator logs)
                // ie. output from k8s-clu-mon and input to the following components (sink or transforms)
                [aggregator.config.name + '_logs']:
                  {
                    type: 'remap',
                    inputs: [baseConverted + '*'],
                    source: '',
                  },

              },
            },

            'destination_metrics.json': {
              // metrics are exposed for scraping at vector aggregator
              sinks: {
                prometheus_exporter: {
                  type: 'prometheus_exporter',
                  inputs: ['internal_metrics'],
                  address: '0.0.0.0:' + aggregator.config.vector.metricsPort,
                  buffer: {
                    type: 'memory',
                    max_events: 2000,
                  },
                  flush_period_secs: 60,  // higher than aggregator.serviceMonitor scrape interval
                },
              },
            },

            'destination_logs.json': {
              // there is no sink for final aggregator's transform for all logs
              // must be defined outside library according to the chosen destination
            },
          }
          + $.aggregator.config.vector.configs
        ,

        configMap:
          configMap.new(aggregator.config.vector.name)
          + configMap.metadata.withNamespace(aggregator.config.namespace)
          + configMap.metadata.withLabels(aggregator.config.commonLabels)
          + configMap.withData(
            {
              [_config]: std.manifestJsonEx(aggregator.configs[_config], '  ')
              for _config in std.objectFields(aggregator.configs)
            }
          )
        ,

        networkPolicy:: {},  // todo
        podDisruptionBudget:: {},  // todo

      }
      + {
        [if debug.on then '__debugMock']:
          {}
          + debug.new('##0', config)
          + debug.new('##21', $.aggregator.config)
          + debug.new('##22', $.aggregator.configs)
          + debug.new('##23', $.aggregator.customMetadata),
      },
  }
