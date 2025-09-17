local esp = import 'espejote.libsonnet';
local config = import 'rabbitmq-lb-service/config.json';

local svcs = esp.context().services;
assert std.length(svcs) == 1 : 'Expected exactly 1 service in services context';
local svc = svcs[0];

{
  apiVersion: 'v1',
  kind: 'Service',
  metadata: {
    annotations: std.get(svc.metadata, 'annotations', {}),
    name: '%s-lb' % svc.metadata.name,
    namespace: svc.metadata.namespace,
  },
  spec: {
    type: 'LoadBalancer',
    loadBalancerClass: '%(loadBalancerClass)s' % config,
    ports: svc.spec.ports,
    selector: svc.spec.selector,
  },
}
