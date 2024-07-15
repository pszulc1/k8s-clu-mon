local k = import 'k.libsonnet';
local namespaceObj = k.core.v1.namespace;
local serviceMonitor = (import 'po.libsonnet').monitoring.v1.serviceMonitor;

local d = import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet';

local global = import 'global.json';
local debug = (import 'debug.libsonnet')(std.thisFile, global.debug);

local utils = import 'utils.libsonnet';


{
  local techVar = {
    local this = self,
    name: 'k8s-clu-mon',  // must be a valid k8s label key name
    externalPrefix: utils.metricLabelName(this.name + '_'),
    promotedPodLabels: [
      'app.kubernetes.io/component',
      'app.kubernetes.io/name',
      'app.kubernetes.io/instance',
      'app.kubernetes.io/part-of',
      'app.kubernetes.io/version',
    ],
    externalLabelsNames: [
      // label name must comply with the metric label format see
      // https://prometheus.io/docs/concepts/data_model/#metric-names-and-labels
      this.externalPrefix + 'cluster',
      this.externalPrefix + 'version',
    ],
  },

  local array2String(array) =
    std.foldl(
      function(result, elem) result + elem,
      std.mapWithIndex(
        function(index, elem) '`' + elem + '`' + if index != std.length(array) - 1 then ', ' else '',
        array
      ),
      ''
    ),


  '#'::
    d.pkg(
      name='k8s-clu-mon',
      url='github.com/!!!!-PROPER-LINK-NEEDED-!!!!',
      help=
      |||
        The jsonnet library that provides the minimal set of k8s components necessary to collect and 
        forward metrics and logs to an external (outside cluster) destination.  
        By design, storing, analysis and monitoring will take place outside the considered cluster.  

        The library uses [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus) with 
        [Prometheus Agent](https://prometheus.io/blog/2021/11/16/agent/) and [Vector](https://vector.dev/) deployed both as an agent and an aggregator.  

        The library monitors indicated application namespaces to collect components metrics and logs. 
        Metrics are scraped by the default `ServiceMonitor`, which is part of a `k8s-clu-mon` or by 
        custom `ServiceMonitor` which must be delivered with the monitored application. 
        Application components log entries are by default provided as `{ payload: 'log entry string' }` JSON. 
        It is up to the monitored application to expose it's `payload` to appropriate JSON data.  
        The library monitors itself as well, i.e. it collects metrics and logs from the components that are part of it. 
        In this case `payload` of selected components logs (eg. prometheus operator and agent, vector aggregator and agent) 
        is already transformed to JSON data.  

        Each metric send to final destination is given additional labels:  
      |||
      + '- the following pods labels '
      + array2String(techVar.promotedPodLabels)
      + 'if defined and after conversion to a valid metric label name, eg. '
      + '`' + utils.metricLabelName(techVar.promotedPodLabels[0]) + '`,  \n'
      + '- '
      + array2String(techVar.externalLabelsNames)
      + ' describing the data source.  \n'
      +
      |||

        All logs provided by `k8s-clu-mon` are available as output from `k8s-clu-mon_logs` transform in 
        [Log Namespacing](https://vector.dev/blog/log-namespacing/) Vector's data model. 
        The `k8s-clu-mon_logs` transform has no consumers by default. 
        Each log entry is given additional `%k8s-clu-mon` metadata, whose `%k8s-clu-mon".labels` contains 
        among others the same set of additional labels as are assigned to each metric and 
        after conversion to a valid metric label name. 
        The particular label will be available in logs metadata only if it is defined for component's pod. 
        This means that `%k8s-clu-mon".labels` assigned for one component's log may be different for another.  

        To use the library, it is necessary to define a destination for 

        - collected metrics, i.e. to define `remoteWrite` for Prometheus Agent, 
        - logs provided by `k8s-clu-mon_logs` transform, i.e. to define a sink which will consume collected logs and for example 
        will apply `%k8s-clu-mon".labels` as stream labels. 

        A basic understanding Prometheus, Prometheus Operator's `ServiceMonitor` and Vector concepts is a must.  

        `./test-instances` defines locally deployed test destionatons for optional usage 
        for convenient tuning data before them sending them to final destionation.  

        See `./examples` for basic usage.  
        See [k8s-clu-mon-example](github.com/!!!!-PROPER-LINK-NEEDED-!!!!) for more intricate working example.  
      |||
      ,
      filename=std.thisFile,
      version=global.version
    )
    +
    d.package.withUsageTemplate('local kcm = import "%(import)s"'),


  '#new'::
    d.fn(
      help=
      |||
        Creates all `k8s-clu-mon` components as an object `{ setup: {...}, monitoring: {...} }`.  
        Parameters: 

        * `namespace` - `k8s-clu-mon` namespace, i.e. the namespace in which all `k8s-clu-mon` components are created,
        * `cluster` - monitored cluster name,
        * `platform` - deployment platform name used by `kube-prometheus` components, see the local variable 
        `platforms` in `./vendor/kube-prometheus/platforms/platforms.libsonnet` for valid values otherwise use `null`.

        For deployment, first apply `.setup` then `.monitoring` components.  
      |||,
      args=[
        d.arg('namespace', d.T.string),
        d.arg('cluster', d.T.string),
        d.arg('platform', d.T.string),
      ]
    ),
  new(namespace, cluster, platform=null):: {

    local base = self,

    config:: {
      local this = self,

      namespace: namespace,
      cluster: cluster,
      name: techVar.name,
      externalPrefix: techVar.externalPrefix,

      commonLabels+: {
        'app.kubernetes.io/part-of': this.name,
        'app.kubernetes.io/version': global.version,
      },
      promotedPodLabels+: techVar.promotedPodLabels,
      externalLabels+: {
        [techVar.externalLabelsNames[0]]: this.cluster,
        [techVar.externalLabelsNames[1]]: global.version,
      },

      monitoredNamespaces+: [],  // namespaces monitored by default: `default`, `kube-system`, base.config.namespace

      'kube-prometheus'+: {
        platform: platform,
        remoteWrite+: [],
      },

      vector+: {
        apiPort: 8686,
        metricsPort: 9090,
        configs+: {},
        envFromSecretRefs+: [],
      },
    },


    local kp = (import 'kp.libsonnet')(base.config),

    setup:
      debug.new('##0', base.config)
      + {
        'kube-prometheus': {
          prometheusOperator:
            kp.prometheusOperator
            { serviceMonitor:: {} },  // prometheusOperator.serviceMonitor deployed in monitoring() due to errors
        },

        namespace:
          namespaceObj.new(base.config.namespace)
          + namespaceObj.metadata.withLabels(
            { 'app.kubernetes.io/name': base.config.namespace }
            + base.config.commonLabels
          ),
      }
    ,

    monitoring:
      debug.new('##0', base.config)
      + {

        'kube-prometheus':
          kp
          {
            blackboxExporter:: {},  // temporarily out of scope
            prometheusAdapter:: {},  // temporarily out of scope

            prometheusOperator: {
              serviceMonitor: kp.prometheusOperator.serviceMonitor,
            },
          },

        defaultServiceMonitor:
          local defaultSmonName = 'default';
          serviceMonitor.new(defaultSmonName)
          + serviceMonitor.metadata.withNamespace(base.config.namespace)
          + serviceMonitor.metadata.withLabels(
            {
              'app.kubernetes.io/component': 'app-service-monitor',
              'app.kubernetes.io/name': defaultSmonName,
            }
            + base.config.commonLabels
          )
          + serviceMonitor.spec.withJobLabel('app.kubernetes.io/name')
          + serviceMonitor.spec.withEndpoints(
            [
              {
                interval: '30s',
                port: 'metrics',
              },
            ]
          )
          + serviceMonitor.spec.namespaceSelector.withMatchNames(base.config.monitoredNamespaces)
          + serviceMonitor.spec.selector.withMatchLabels({ metrics_exposed: 'true' }),


        vector: (import 'vector.libsonnet')(base.config),

      },

  },


  '#withMonitoredNamespacesMixin'::
    d.fn(
      help=
      |||
        Adds application namespaces for monitoring.  
        By default metrics and logs from `default`, `kube-system` and `k8s-clu-mon` namespace are monitored only.  
        Parameters: 

        * `namespaces` - array of namespaces names.

        Note: Any added namespace must exist before `k8s-clu-mon` is deployed, otherwise 
        an error regarding `Role` and `RoleBinding` will arise.  
      |||,
      args=[
        d.arg('namespaces', d.T.array),
      ]
    ),
  withMonitoredNamespacesMixin(namespaces):: {
    config+: {
      monitoredNamespaces: std.set(super.monitoredNamespaces + namespaces),  // duplication excluded
    },
  },


  '#withPrometheusRemoteWriteMixin'::
    d.fn(
      help=
      |||
        Adds Prometheus `remoteWrite` objects for Prometheus Agent.  
        Parameters: 

        * `remoteWrites` - array of `remoteWrite` objects.

        `remoteWrite` must be defined in accordance with the CRD definition: 
        `jsonnet vendor/prometheus-operator/prometheusagents-crd.json | jq '.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.remoteWrite.items.properties|keys'`.  
        See also [Prometheus `remote_write` configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#remote_write).  
        By default there is no any `remoteWrite` defined.  
      |||,
      args=[
        d.arg('remoteWrites', d.T.array),
      ]
    ),
  withPrometheusRemoteWriteMixin(remoteWrites):: {
    config+: {
      'kube-prometheus'+: { remoteWrite+: remoteWrites },
    },
  },


  '#withVectorConfigsMixin'::
    d.fn(
      help=
      |||
        Adds another Vector config file to Vector aggregator configuration.  
        If the given file already exists, it will be redefined.  
        Parameters: 

        * `configs` - an object of config files, e.g. `{ 'config_file1.json': {...}, 'config_file2.json': {...} }`.

        The content of each config file must be valid JSON data compliant with the Vector configuration 
        (see [Configuring Vector](https://vector.dev/docs/reference/configuration/)).  

        `k8s-clu-mon` default configuration of Vector aggregator is already split into several config files and 
        defines `k8s-clu-mon_logs` transform, which is the output for all collected logs and by default has no consumer. 
        So at least, the destination for logs must be defined, either by redefining the `destination_logs.json` file (empty by default), 
        or otherwise to contain sink which will consume collected logs.  
        See `./examples` to learn how to get defined config files or to redefine one.  

        In any case, all config files must form a consistent Vector aggregator configuration.  
      |||,
      args=[
        d.arg('configs', d.T.object),
      ]
    ),
  withVectorConfigsMixin(configs):: {
    config+: {
      vector+: {
        configs+: configs,
      },
    },
  },


  '#withVectorEnvFromSecretRefMixin'::
    d.fn(
      help=
      |||
        For aggregator container adds secret names from which environment variables will be set.  
        Equivalent to the `envFrom` part of the container definition.  
        Parameters: 

        * `secretNames` - array of secret names.

        Usefull in defining Vector configuration. 
        See [k8s-clu-mon-example](github.com/!!!!-PROPER-LINK-NEEDED-!!!!) for working example.  
      |||,
      args=[
        d.arg('namespaces', d.T.array),
      ]
    ),
  withVectorEnvFromSecretRefMixin(secretNames):: {
    config+: {
      vector+: {
        envFromSecretRefs: std.set(super.envFromSecretRefs + secretNames),  // duplication excluded
      },
    },
  },

}
