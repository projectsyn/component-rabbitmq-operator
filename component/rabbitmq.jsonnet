// rabbitmq.jsonnet
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
      name: params.rbac.group,
      apiGroup: 'rbac.authorization.k8s.io',
    },
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

if params.enabled then {
  '10_namespace': namespace,
  '20_rabbitmq_cluster': rabbitmqCluster,
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
