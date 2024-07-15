/*
Jsonnet to generate base/*.json
*/

local kcm = import '../main.libsonnet';

local result = kcm.new('my-namespace', 'my-cluster');

{
  'namespace.json': result.setup.namespace,
  'setup-kp-po-contents.json': std.objectFields(result.setup['kube-prometheus'].prometheusOperator),

  'default-service-monitor.json': result.monitoring.defaultServiceMonitor,
  'main-kp-contents.json': std.objectFields(result.monitoring['kube-prometheus']),
  'main-kp-po-contents.json': std.objectFields(result.monitoring['kube-prometheus'].prometheus),
  'prometheus-agent.json': result.monitoring['kube-prometheus'].prometheus.prometheusAgent,
}
