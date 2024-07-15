/*
Loki instance for test purposes, e.g. for analysis logs before sending them to Grafana Cloud.
It is not monitored ie. the apropriate ServiceMonitor is not defined.

Simple Scalable Deployment (SSD) mode chosen, see: https://grafana.com/docs/loki/latest/get-started/deployment-modes/#simple-scalable
The specific version of jsonnet library used: https://github.com/grafana/loki/tree/main/production/ksonnet/loki-simple-scalable

Due to changes probably it would be easier to choose a Monolithic mode?
*/

local k = import '../k.libsonnet';
local persistentVolumeClaim = k.core.v1.persistentVolumeClaim;
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;
local container = k.core.v1.container;
local statefulSet = k.apps.v1.statefulSet;

local pvc = k.core.v1.persistentVolumeClaim;
local meta = k.meta.v1.objectMeta;

local lokiSSD = import 'loki-simple-scalable/example/main.jsonnet';

local debug = (import '../debug.libsonnet')(std.thisFile, (import '../global.json').debug);


function(namespace, commonLabels)
  lokiSSD
  + {
    [_component]+: {
      metadata+:
        meta.withLabelsMixin(commonLabels)
        + meta.withNamespace(namespace),
    }
    for _component in std.objectFields(lokiSSD)
  }
  + {
    read_statefulset+:
      statefulSet.spec.template.metadata.withLabelsMixin(commonLabels)
      + statefulSet.spec.template.metadata.withNamespace(namespace)
    ,
    write_statefulset+:
      statefulSet.spec.template.metadata.withLabelsMixin(commonLabels)
      + statefulSet.spec.template.metadata.withNamespace(namespace),
  }
  + {
    _config+:: {
      commonArgs+:: {
        //'log-config-reverse-order': true  // full config for debug purposes
      },
      loki+: {
        analytics: {
          reporting_enabled: false,
        },
        common+: {
          path_prefix: '/data',
          storage: {
            filesystem: {
              chunks_directory: '/data/chunks',
              rules_directory: '/data/rules',
            },
          },
        },
        memberlist: {
          join_members: [
            '%s.%s.svc.cluster.local' % [$._config.headless_service_name, namespace],
          ],
        },
        schema_config+: {
          configs: [
            {
              from: '2024-03-22',
              index: {
                period: '24h',
                prefix: 'index_',
              },
              object_store: 'filesystem',
              store: 'tsdb',
              schema: 'v12',
            },
          ],
        },
      },
    },

    'read-write-pvc':
      persistentVolumeClaim.new('read-write-pvc')
      // ReadWriteMany causes pvc & pods 'Pending' due to volumeBindingMode=WaitForFirstConsumer set in standard storageClass @kind
      + pvc.spec.withAccessModes('ReadWriteOnce')
      + pvc.spec.resources.withRequests({ storage: '10Gi' })
      + pvc.metadata.withLabelsMixin(commonLabels)
      + pvc.metadata.withNamespace(namespace)
    ,

    'read-write-volume':: volume.fromPersistentVolumeClaim('read-write', $['read-write-pvc'].metadata.name),

    read_container+::
      container.withVolumeMounts([volumeMount.new($['read-write-volume'].name, '/data')])
    ,
    write_container+::
      container.withVolumeMounts([volumeMount.new($['read-write-volume'].name, '/data')])
    ,

    read_statefulset+:
      {
        spec+: {
          volumeClaimTemplates:: {},
        },
      }
      + statefulSet.spec.template.spec.withVolumesMixin($['read-write-volume'])
    ,
    write_statefulset+:
      {
        spec+: {
          volumeClaimTemplates:: {},
        },
      }
      + statefulSet.spec.template.spec.withVolumesMixin($['read-write-volume']),

  }
  + {
    [if debug.on then '__debugMock']:
      debug.new('##0', { namespace: namespace, commonLabels: commonLabels }),
  }
