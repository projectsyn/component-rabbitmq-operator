// main template for rabbitmq-operator
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.rabbitmq_operator;
local namespace = params.namespace;
local caCertificateSecretName = params.operator.helmValues.msgTopologyOperator.existingWebhookCertSecret;

{
  '00_namespace': kube.Namespace(namespace),
}
