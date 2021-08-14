local kp =
  (import 'kube-prometheus/main.libsonnet') +
  // Uncomment the following imports to enable its patches
  // (import 'thanos-mixin/alerts/query.libsonnet') +
  (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  (import 'kube-prometheus/platforms/kubeadm.libsonnet') +
  (import 'kubernetes-mixin/rules/rules.libsonnet') +
  // (import 'prometheus_rules/custom_rules.libsonnet') +
  (import 'kube-prometheus/addons/all-namespaces.libsonnet') +
  {
    values+:: {
      common+: {
        namespace: 'monitoring',
      },
      alertmanager+: {
        config: importstr 'alertmanager/alertmanager-secrets.yaml',
      },
      grafana+:: {
        folderDashboards+:: {
          Custom: {
            'node-exporter-full.json': (import 'grafana-dashboards/node-exporter-full.json'),
          },
          // Thanos: {
          //   'bucketreplicate.json': (import 'grafana-dashboards/thanos/bucket_replicate.json'),
          //   'compact.json': (import 'grafana-dashboards/thanos/compact.json'),
          //   'overview.json': (import 'grafana-dashboards/thanos/overview.json'),
          //   'query.json': (import 'grafana-dashboards/thanos/query.json'),
          //   'receive.json': (import 'grafana-dashboards/thanos/receive.json'),
          //   'rule.json': (import 'grafana-dashboards/thanos/rule.json'),
          //   'sidecar.json': (import 'grafana-dashboards/thanos/sidecar.json'),
          //   'store.json': (import 'grafana-dashboards/thanos/store.json'),
          // },
        },
        dashboards+:: {
            'kube-router.json': (import 'grafana-dashboards/kube-router.json'),
            'coredns.json': (import 'grafana-dashboards/coredns.json'),
            //'minio.json': (import 'grafana-dashboards/minio.json'),
            'cert-manager.json': (import 'grafana-dashboards/cert-manager.json'),
        },
        datasources+:: [{
          name: 'prometheus',
          type: 'prometheus',
          access: 'proxy',
          orgId: 1,
          url: 'http://prometheus-k8s.monitoring.svc.cluster.local:9090',
          version: 1,
          editable: false,
        }],
        env: [
          { name: 'GF_SERVER_DOMAIN', value: 'grafana.monitoring.svc.cluster.local' },
          { name: 'GF_SERVER_ROOT_URL', value: 'http://grafana.monitoring.svc.cluster.local:3000' },
          { name: 'GF_AUTH_GENERIC_OAUTH_ENABLED', value: 'true' },
          { name: 'GF_AUTH_GENERIC_OAUTH_NAME', value: 'Login Keycloak' },
          { name: 'GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP', value: 'true' },
          { name: 'GF_AUTH_GENERIC_OAUTH_CLIENT_ID', value: 'grafana' },
          { name: 'GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET', valueFrom: {secretKeyRef: {name: 'grafana-credentials', key: 'client-secret',}}},
          { name: 'GF_AUTH_GENERIC_OAUTH_SCOPES', value: 'openid profile email' },
          { name: 'GF_AUTH_GENERIC_OAUTH_EMAIL_ATTRIBUTE_NAME', value: 'email:primary' },
          { name: 'GF_AUTH_GENERIC_OAUTH_TLS_SKIP_VERIFY_INSECURE', value: 'true' },
          { name: 'GF_AUTH_GENERIC_OAUTH_AUTH_URL', value: 'https://keycloak.keycloak.svc.cluster.local:8443/auth/realms/input-error/protocol/openid-connect/auth' },
          { name: 'GF_AUTH_GENERIC_OAUTH_TOKEN_URL', value: 'https://keycloak.keycloak.svc.cluster.local:8443/auth/realms/input-error/protocol/openid-connect/token' },
          { name: 'GF_AUTH_GENERIC_OAUTH_API_URL', value: 'https://keycloak.keycloak.svc.cluster.local:8443/auth/realms/input-error/protocol/openid-connect/userinfo' },
          { name: 'GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH', value: "contains(roles[*], 'admin') && 'Admin' || contains(roles[*], 'editor') && 'Editor' || 'Viewer'" },
          { name: 'GF_SECURITY_ADMIN_PASSWORD', valueFrom: {secretKeyRef: {name: 'grafana-credentials', key: 'password',}}},
        ],
      },
    },
    alertmanager+: {
      alertmanager+: {
        spec+: {
          externalUrl: "http://alertmanager.monitoring.svc.cluster.local:9093",
          secrets: ['prometheus-tls'],
        },
      },
    },
    prometheus+: {
      certManagerRules: {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'PrometheusRule',
        metadata: {
          name: 'cert-manager-rules',
          namespace: $.values.common.namespace,
          labels: {
            prometheus: 'k8s',
            role: 'alert-rules',
          }
        },
        spec: {
          groups: (import 'prometheus_rules/cert-manager_rules.json').groups,
        },
      },
      coreDNSRules: {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'PrometheusRule',
        metadata: {
          name: 'coredns-rules',
          namespace: $.values.common.namespace,
          labels: {
            prometheus: 'k8s',
            role: 'alert-rules',
          }
        },
        spec: {
          groups: (import 'prometheus_rules/coreDNS-alerts.json').groups,
        },
      },
      prometheusAdditionalScrapeConfig: {
        apiVersion: 'v1',
        data: {
          'prometheus-additional.yaml': std.base64(importstr 'secrets/prometheus-additonalScrapeConfigs.yaml'),
        },
        kind: 'Secret',
        metadata: {
          name: 'additionalscrapeconfigs',
          namespace: 'monitoring',
        },
      },
      'grafanaCredentials-secrets': {
        apiVersion: 'v1',
        data: {
          'password': std.base64(importstr 'secrets/grafana-credentials.pass'),
          'client-secret': std.base64(importstr 'secrets/grafana-client-secret.pass'),
        },
        kind: 'Secret',
        metadata: {
          name: 'grafana-credentials',
          namespace: 'monitoring',
        },
      },
      prometheus+: {
        spec+: {  // https://github.com/coreos/prometheus-operator/blob/master/Documentation/api.md#prometheusspec
          // If a value isn't specified for 'retention', then by default the '--storage.tsdb.retention=24h' arg will be passed to prometheus by prometheus-operator.
          // The possible values for a prometheus <duration> are:
          //  * https://github.com/prometheus/common/blob/c7de230/model/time.go#L178 specifies "^([0-9]+)(y|w|d|h|m|s|ms)$" (years weeks days hours minutes seconds milliseconds)
          retention: '2d',

          // Reference info: https://github.com/coreos/prometheus-operator/blob/master/Documentation/user-guides/storage.md
          // By default (if the following 'storage.volumeClaimTemplate' isn't created), prometheus will be created with an EmptyDir for the 'prometheus-k8s-db' volume (for the prom tsdb).
          // This 'storage.volumeClaimTemplate' causes the following to be automatically created (via dynamic provisioning) for each prometheus pod:
          //  * PersistentVolumeClaim (and a corresponding PersistentVolume)
          //  * the actual volume (per the StorageClassName specified below)
          storage: {  // https://github.com/coreos/prometheus-operator/blob/master/Documentation/api.md#storagespec
            volumeClaimTemplate: {  // https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.11/#persistentvolumeclaim-v1-core (defines variable named 'spec' of type 'PersistentVolumeClaimSpec')
              apiVersion: 'v1',
              kind: 'PersistentVolumeClaim',
              spec: {
                accessModes: ['ReadWriteOnce'],
                // https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.11/#resourcerequirements-v1-core (defines 'requests'),
                // and https://kubernetes.io/docs/concepts/policy/resource-quotas/#storage-resource-quota (defines 'requests.storage')
                resources: { requests: { storage: '25Gi' } },
                storageClassName: 'synology-iscsi-storage',
              },
            },
          },  // storage
          externalUrl: "http://prometheus.monitoring.svc.cluster.local:9090",
          secrets: ['additionalscrapeconfigs', 'prometheus-tls'],
          additionalScrapeConfigs: {
            name: 'additionalscrapeconfigs',
            key: 'prometheus-additional.yaml',
          },
          nodeSelector: {
            'kubernetes.io/os': 'linux'
          },
          podMetadata+: {
            annotations: {
              'secret.reloader.stakater.com/reload': "prometheus-tls",
            },
          },
        },  // spec
      },  // prometheus
    },
  };

{ 'setup/0namespace-namespace': kp.kubePrometheus.namespace } +
{
  ['setup/prometheus-operator-' + name]: kp.prometheusOperator[name]
  for name in std.filter((function(name) name != 'serviceMonitor' && name != 'prometheusRule'), std.objectFields(kp.prometheusOperator))
} +
// serviceMonitor and prometheusRule are separated so that they can be created after the CRDs are ready
{ 'prometheus-operator-serviceMonitor': kp.prometheusOperator.serviceMonitor } +
{ 'prometheus-operator-prometheusRule': kp.prometheusOperator.prometheusRule } +
{ 'kube-prometheus-prometheusRule': kp.kubePrometheus.prometheusRule } +
{ ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
{ ['blackbox-exporter-' + name]: kp.blackboxExporter[name] for name in std.objectFields(kp.blackboxExporter) } +
{ ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) } +
{ ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['kubernetes-' + name]: kp.kubernetesControlPlane[name] for name in std.objectFields(kp.kubernetesControlPlane) }
{ ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
{ ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
{ ['prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) }
