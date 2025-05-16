// main template for rabbitmq-operator
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.rabbitmq_operator;
local namespace = params.namespace;
local caCertificateSecretName = params.operator.helmValues.msgTopologyOperator.existingWebhookCertSecret;

local selfSignedIssuer = {
  apiVersion: 'cert-manager.io/v1',
  kind: 'Issuer',
  metadata: {
    name: 'messaging-topology-operator-webhook',
    namespace: namespace,
  },
  spec: {
    selfSigned: {},
  },
};

local caCertificate = {
  apiVersion: 'cert-manager.io/v1',
  kind: 'Certificate',
  metadata: {
    name: 'messaging-topology-operator-webhook',
    namespace: namespace,
  },
  spec: {
    secretName: caCertificateSecretName,
    dnsNames: [
      'rabbitmq-operator-rabbitmq-messaging-topology-operator-webhook.' + namespace + '.svc',
      'rabbitmq-operator-rabbitmq-messaging-topology-operator-webhook.' + namespace + '.svc.cluster.local',
    ],
    issuerRef: {
      kind: 'Issuer',
      name: 'messaging-topology-operator-webhook',
    },
  },
};

{
  '00_namespace': kube.Namespace(namespace),
  '10_messaging_topology_operator_webhook_issuer': selfSignedIssuer,
  '20_messaging_topology_operator_webhook_certificate': caCertificate,
}
