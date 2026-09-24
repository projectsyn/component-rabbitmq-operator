local com = import 'lib/commodore.libjsonnet';
local params = com.inventory().parameters.rabbitmq_operator;
local scopeNamespace = params.operator.OPERATOR_SCOPE_NAMESPACE;
local deploy_file = std.extVar('output_path') + '/deployment.yaml';
local deploy_obj = com.yaml_load(deploy_file);
{
  deployment: if scopeNamespace == null then deploy_obj else deploy_obj {
    spec+: {
      template+: {
        spec+: {
          containers: [
            if c.name == 'rabbitmq-cluster-operator' then c {
              env+: [
                { name: 'OPERATOR_SCOPE_NAMESPACE', value: scopeNamespace },
              ],
            } else c
            for c in super.containers
          ],
        },
      },
    },
  },
}
