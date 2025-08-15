local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.rabbitmq_operator.prober;

local envFromSecret(name, key, secretName) = {
  name: name,
  valueFrom: {
    secretKeyRef: {
      name: secretName,
      key: key,
    },
  },
};

local envVar(name, value) = {
  name: name,
  value: std.toString(value),
};

// Deployment
local deployment = kube.Deployment(params.name) {
  metadata+: {
    namespace: params.namespace,
    labels: {
      app: params.name,
    },
  },
  spec+: {
    replicas: 1,
    selector: {
      matchLabels: {
        app: params.name,
      },
    },
    template: {
      metadata: {
        labels: {
          app: params.name,
        },
      },
      spec: {
        containers: [
          {
            name: 'prober',
            image: params.image,
            env: [
              envFromSecret('RABBITMQ_HOST', 'host', params.secretName),
              envFromSecret('RABBITMQ_PORT', 'port', params.secretName),
              envFromSecret('RABBITMQ_USER', 'username', params.secretName),
              envFromSecret('RABBITMQ_PASSWORD', 'password', params.secretName),
              envVar('PROBE_INTERVAL', params.probeInterval),
              envVar('METRICS_PORT', params.metricsPort),
              envVar('RABBITMQ_USE_TLS', params.useTLS),
            ],
            ports: [
              {
                containerPort: params.metricsPort,
                name: 'metrics',
              },
            ],
            resources: params.resources,
            livenessProbe: {
              httpGet: {
                path: '/',
                port: params.metricsPort,
              },
            },
            readinessProbe: {
              httpGet: {
                path: '/',
                port: params.metricsPort,
              },
            },
          },
        ],
        restartPolicy: 'Always',
        volumes: [],
      },
    },
  },
};

// Service
local service = kube.Service(params.name + '-service') {
  metadata+: {
    namespace: params.namespace,
    labels: {
      app: params.name,
    },
  },
  spec+: {
    selector: {
      app: params.name,
    },
    ports: [
      {
        name: 'metrics',
        port: params.metricsPort,
        targetPort: params.metricsPort,
        protocol: 'TCP',
      },
    ],
  },
};

// ServiceMonitor
local serviceMonitor = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'ServiceMonitor',
  metadata: {
    name: params.name,
    namespace: params.namespace,
    labels: {
      app: params.name,
    },
  },
  spec: {
    selector: {
      matchLabels: {
        app: params.name,
      },
    },
    endpoints: [
      {
        port: 'metrics',
        interval: params.monitoring.interval,
        path: '/metrics',
        relabelings: [
          {
            sourceLabels: [],
            targetLabel: 'instance',
            replacement: params.name + '-service.monitoring.svc.cluster.local:' + params.metricsPort,
          },
        ],
      },
    ],
  },
};

// PrometheusRule for recording rules
local prometheusRule = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    name: params.name + '-recording-rules',
    namespace: params.namespace,
  },
  spec: {
    groups: [
      {
        name: 'rabbitmq.sla.recording',
        interval: params.monitoring.recordingRulesInterval,
        rules: [
          {
            record: 'rabbitmq:availability:current',
            expr: 'max(rabbitmq_functional_availability{job="' + params.name + '-service"})',
          },
          {
            record: 'rabbitmq:availability:rate5m',
            expr: 'avg_over_time(rabbitmq:availability:current[5m])',
          },
          {
            record: 'rabbitmq:availability:rate1h',
            expr: 'avg_over_time(rabbitmq:availability:current[1h])',
          },
          {
            record: 'rabbitmq:availability:rate24h',
            expr: 'avg_over_time(rabbitmq:availability:current[24h])',
          },
          {
            record: 'rabbitmq:sla_percentage',
            expr: 'rabbitmq:availability:rate24h * 100',
          },
        ],
      },
    ],
  },
};


if params.enabled then {
  '20_prober_deployment': deployment,
  '21_prober_service': service,
  '22_prober_service_monitor': serviceMonitor,
  '22_prober_service_prom_rule': prometheusRule,
} else {}
