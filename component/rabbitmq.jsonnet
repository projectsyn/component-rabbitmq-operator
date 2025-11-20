// rabbitmq.jsonnet
local com = import 'lib/commodore.libjsonnet';
local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.rabbitmq_operator.rabbitmq;

local namespace = kube.Namespace(params.namespace) {
  metadata+: {
    labels+: params.namespaceLabels,
  },
  spec: {},
};

local rabbitmqCluster = {
  apiVersion: 'rabbitmq.com/v1beta1',
  kind: 'RabbitmqCluster',
  metadata: {
    name: params.name,
    namespace: params.namespace,
  },
  spec: {
    rabbitmq: {
      additionalPlugins: params.plugins,
    },
    image: params.image,
    persistence: {
      storage: params.persistence.storage,
    },
    replicas: params.replicas,
    resources: params.resources,
    service: params.service,
    override: {
      statefulSet: {
        spec: {
          template: {
            spec: {
              containers: [],
              securityContext: {},
            } + (
              if params.affinity != null && params.affinity != {} then {
                affinity: params.affinity,
              } else {}
            ),
          },
        },
      },
    },
  } + (
    if params.tls.enabled then {
      tls: {
        secretName: params.tls.secretName,
        disableNonTLSListeners: params.tls.disableNonTLSListeners,
      },
    } else {}
  ),
};

local role = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'Role',
  metadata: {
    name: 'read-access',
    namespace: params.namespace,
  },
  rules: [
    {
      apiGroups: [ '' ],
      resources: [ 'pods', 'secrets', 'configmaps', 'services' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
    {
      apiGroups: [ 'apps' ],
      resources: [ 'deployments', 'statefulsets' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
    {
      apiGroups: [ 'route.openshift.io' ],
      resources: [ 'routes' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};

local legacyGroups = std.filter(
  function(group) group != '',
  com.renderArray(params.rbac.groups + [ std.get(params.rbac, 'group', '') ])
);
local roleBinding = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'RoleBinding',
  metadata: {
    name: 'read-access-binding',
    namespace: params.namespace,
  },
  subjects: [
    {
      kind: 'Group',
      name: group,
      apiGroup: 'rbac.authorization.k8s.io',
    }
    for group in legacyGroups
  ],
  roleRef: {
    kind: 'Role',
    name: 'read-access',
    apiGroup: 'rbac.authorization.k8s.io',
  },
};

local amqpsRoute = {
  apiVersion: 'route.openshift.io/v1',
  kind: 'Route',
  metadata: {
    name: 'amqps',
    namespace: params.namespace,
  },
  spec: {
    host: params.tls.dnsNames.amqps,
    to: {
      kind: 'Service',
      name: params.name,
    },
    port: {
      targetPort: 'amqps',
    },
    tls: {
      termination: 'passthrough',
    },
  },
};

local managementRoute = {
  apiVersion: 'route.openshift.io/v1',
  kind: 'Route',
  metadata: {
    name: 'management',
    namespace: params.namespace,
  },
  spec: {
    host: params.tls.dnsNames.management,
    to: {
      kind: 'Service',
      name: params.name,
    },
    port: {
      targetPort: 'management-tls',
    },
    tls: {
      termination: 'passthrough',
    },
  },
};

local espSA = kube.ServiceAccount('rabbitmq-lb-service-manager') {
  metadata+: {
    namespace: params.namespace,
  },
};

local espRole = kube.Role('rabbitmq-lb-service-manager') {
  metadata+: {
    namespace: params.namespace,
  },
  rules: [
    {
      apiGroups: [ '' ],
      resources: [ 'services' ],
      verbs: [ '*' ],
    },
    {
      apiGroups: [ 'espejote.io' ],
      resources: [ 'jsonnetlibraries' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};

local espRoleBinding = kube.RoleBinding('rabbitmq-lb-service-manager') {
  metadata+: {
    namespace: params.namespace,
  },
  roleRef_: espRole,
  subjects_: [ espSA ],
};

local espConfig =
  esp.jsonnetLibrary('rabbitmq-lb-service', params.namespace) {
    spec: {
      data: {
        'config.json': std.manifestJson(params.custom_lb_service),
      },
    },
  };

local espLBService =
  esp.managedResource('rabbitmq-lb-service', params.namespace) {
    metadata+: {
      annotations: {
        'syn.tools/description': |||
          This ManagedResource watches the Service created by the
          rabbitmq-operator for the RabbitmqCluster resource that's created by
          the Commodore component.

          The ManagedResource creates a copy of the RabbitmqCluster's primary
          service with `spec.type=LoadBalancer` and a user-configurable
          `spec.loadBalancerClass`. The values of `metadata.annotations`,
          `spec.ports` and `spec.selector` are copied from the
          operator-managed Service and updated whenever the operator makes any
          changes.
        |||,
      },
    },
    spec: {
      applyOptions: {
        force: true,
      },
      context: [
        {
          name: 'services',
          resource: {
            apiVersion: 'v1',
            kind: 'Service',
            // NOTE(sg): Assumption here is that the service has the same name
            // as the RabbitmqCluster custom resource.
            name: params.name,
            namespace: params.namespace,
          },
        },
      ],
      triggers: [
        {
          name: 'service',
          watchContextResource: {
            name: 'services',
          },
        },
        {
          name: 'jsonnetlib',
          watchResource: {
            apiVersion: 'espejote.io/v1alpha1',
            kind: 'JsonnetLibrary',
            name: espConfig.metadata.name,
            namespace: params.namespace,
          },
        },
      ],
      serviceAccountRef: {
        name: espSA.metadata.name,
      },
      template: importstr 'espejote-templates/rabbitmq-lb-service.jsonnet',
    },
  };

local needs_cnp = std.member(inv.applications, 'cilium');
local cnp =
  kube._Object('cilium.io/v2', 'CiliumNetworkPolicy', '%s-allow-from-world' % params.name) {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      endpointSelector: {
        matchLabels: {
          // NOTE(sg): Assumption here is that the pods have label
          // `app.kubernetes.io/name=<name of RabbitmqCluster custom resource>`
          'app.kubernetes.io/name': params.name,
        },
      },
      ingress: [ {
        fromEntities: [ 'world' ],
        toPorts: [ {
          ports: [
            { port: '5671', protocol: 'TCP' },
            { port: '5672', protocol: 'TCP' },
          ],
        } ],
      } ],
    },
  };

if params.enabled then {
  '10_namespace': namespace,
  '20_rabbitmq_cluster': rabbitmqCluster,
  [if needs_cnp then '30_rabbitmq_cilium_networkpolicy']: cnp,
  [if params.custom_lb_service.enabled then '99_rabbitmq_lb_service']:
    [ espSA, espRole, espRoleBinding, espConfig, espLBService ],
} + (
  if params.rbac.enabled then {
    '30_rbac_role': role,
    '31_rbac_role_binding': roleBinding,
  } else {}
) + (
  if params.tls.enabled then {
    '40_amqps_route': amqpsRoute,
    '40_management_route': managementRoute,
  } else {}
) else {}
