#!/bin/bash
source "$(dirname "${BASH_SOURCE}")/../../hack/lib/init.sh"
trap os::test::junit::reconcile_output EXIT

# Cleanup cluster resources created by this test
(
  set +e
  oc delete all,templates,secrets,pods,jobs --all
  oc delete image v1-image
  oc delete group patch-group
  oc delete project test-project-admin
  oc delete oauthaccesstokens.oauth.openshift.io/DYGZDLucARCPIfUeKPhsgPfn0WBLR_9KdeREH0c9iod
  oc delete -f ${TEST_DATA}/multiport-service.yaml
  exit 0
) &>/dev/null

function escape_regex() {
  sed 's/[]\.|$(){}?+*^]/\\&/g' <<< "$*"
}

project="$( oc project -q )"

os::test::junit::declare_suite_start "cmd/basicresources"
# This test validates basic resource retrieval and command interaction

os::test::junit::declare_suite_start "cmd/basicresources/versionreporting"
# Test to make sure that we're reporting the correct version information from endpoints and the correct
# User-Agent information from our clients regardless of which resources they're trying to access
#os::build::version::get_vars
#os_git_regex="$( escape_regex "${OS_GIT_VERSION%%-*}" )"
#kube_git_regex="$( escape_regex "${KUBE_GIT_VERSION%%-*}" )"
#etcd_version="$(echo "${ETCD_GIT_VERSION}" | sed -E "s/\-.*//g" | sed -E "s/v//")"
#etcd_git_regex="$( escape_regex "${etcd_version%%-*}" )"
#os::cmd::expect_success_and_text 'oc version' "Client Version: .*GitVersion:\"${os_git_regex}"
#os::cmd::expect_success_and_text 'oc version' "Server Version: .*GitVersion:\"${kube_git_regex}"
#os::cmd::expect_success_and_text "curl -k '${API_SCHEME}://${API_HOST}:${API_PORT}/version'" "${kube_git_regex}"
#os::cmd::expect_success_and_text "curl -k '${API_SCHEME}://${API_HOST}:${API_PORT}/version'" "${OS_GIT_COMMIT}"

# variants I know I have to worry about
# 1. oc (kube and openshift resources)
# 2. oc adm (kube and openshift resources)

# example User-Agent: oc/v1.2.0 (linux/amd64) kubernetes/bc4550d
#os::cmd::expect_success_and_text 'oc get pods --loglevel=7  2>&1 | grep -A4 "pods" | grep User-Agent' "oc/${kube_git_regex} .* kubernetes/"
## example User-Agent: oc/v1.2.0 (linux/amd64) kubernetes/bc4550d
#os::cmd::expect_success_and_text 'oc get dc --loglevel=7  2>&1 | grep -A4 "deploymentconfig" | grep User-Agent' "oc/${kube_git_regex} .* kubernetes/"
## example User-Agent: oc/v1.1.3 (linux/amd64) openshift/b348c2f
#os::cmd::expect_success_and_text 'oc adm policy who-can get pods --loglevel=7  2>&1 | grep -A4 "localresourceaccessreviews" | grep User-Agent' "oc/${kube_git_regex} .* kubernetes/"
#echo "version reporting: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/basicresources/status"
os::cmd::expect_success_and_text 'oc status -h' 'oc describe buildconfig'
os::cmd::expect_success_and_text 'oc status' 'oc new-app'
echo "status help output: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/basicresources/explain"
os::cmd::expect_failure_and_text 'oc get' 'oc api-resources'
os::cmd::expect_success_and_text 'oc get all --loglevel=6' 'buildconfigs'
os::cmd::expect_success_and_text 'oc explain pods' 'Pod is a collection of containers that can run on a host'
os::cmd::expect_success_and_text 'oc explain pods.spec' 'SecurityContext holds pod-level security attributes'
# TODO unbreak explain
#os::cmd::expect_success_and_text 'oc explain deploymentconfig' 'a desired deployment state'
#os::cmd::expect_success_and_text 'oc explain deploymentconfig.spec' 'ensures that this deployment config will have zero replicas'
echo "explain: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/basicresources/resource-builder"
# Test resource builder filtering of files with expected extensions inside directories, and individual files without expected extensions
os::cmd::expect_success 'oc create -f ${TEST_DATA}/resource-builder/directory -f ${TEST_DATA}/resource-builder/json-no-extension -f ${TEST_DATA}/resource-builder/yml-no-extension'
# Explicitly specified extensionless files
os::cmd::expect_success 'oc get secret json-no-extension yml-no-extension'
# Scanned files with extensions inside directories
os::cmd::expect_success 'oc get secret json-with-extension yml-with-extension'
# Ensure extensionless files inside directories are not processed by resource-builder
os::cmd::expect_failure_and_text 'oc get secret json-no-extension-in-directory' 'not found'
echo "resource-builder: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/basicresources/pods"
os::cmd::expect_success 'oc get pods'
os::cmd::expect_success_and_text 'oc create -f ${TEST_DATA}/hello-openshift/hello-pod.json' 'pod/hello-openshift created'
os::cmd::expect_success 'oc describe pod hello-openshift'
os::cmd::expect_success 'oc delete pods hello-openshift --grace-period=0 --force'
echo "pods: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/basicresources/label"
os::cmd::expect_success_and_text 'oc create -f ${TEST_DATA}/hello-openshift/hello-pod.json -o name' 'pod/hello-openshift'
os::cmd::try_until_success 'oc label pod/hello-openshift acustom=label' # can race against scheduling and status updates
os::cmd::expect_success_and_text 'oc describe pod/hello-openshift' 'acustom=label'
os::cmd::try_until_success 'oc annotate pod/hello-openshift foo=bar' # can race against scheduling and status updates
os::cmd::expect_success_and_text 'oc get -o yaml pod/hello-openshift' 'foo: bar'
os::cmd::expect_failure_and_not_text 'oc annotate pod hello-openshift description="test" --resource-version=123' 'may only be used with a single resource'
os::cmd::expect_failure_and_text 'oc annotate pod hello-openshift hello-openshift description="test" --resource-version=123' 'may only be used with a single resource'
os::cmd::expect_success 'oc delete pods -l acustom=label --grace-period=0 --force'
os::cmd::expect_failure 'oc get pod/hello-openshift'

# show-labels should work for projects
os::cmd::expect_success "oc label namespace '${project}' foo=bar"
os::cmd::expect_success_and_text "oc get project '${project}' --show-labels" "foo=bar"

echo "label: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/basicresources/services"
os::cmd::expect_success 'oc get services'
os::cmd::expect_success 'oc create -f ${TEST_DATA}/test-service.json'
os::cmd::expect_success 'oc delete services frontend'
echo "services: ok"
os::test::junit::declare_suite_end

# TODO rewrite the yaml for this test to actually work
os::test::junit::declare_suite_start "cmd/basicresources/list-version-conversion"
os::cmd::expect_success 'oc create   -f ${TEST_DATA}/mixed-api-versions.yaml'
os::cmd::expect_success 'oc get      -f ${TEST_DATA}/mixed-api-versions.yaml -o yaml'
os::cmd::expect_success 'oc label    -f ${TEST_DATA}/mixed-api-versions.yaml mylabel=a'
os::cmd::expect_success 'oc annotate -f ${TEST_DATA}/mixed-api-versions.yaml myannotation=b'
# Make sure all six resources, with different API versions, got labeled and annotated
os::cmd::expect_success_and_text 'oc get -f ${TEST_DATA}/mixed-api-versions.yaml --output=jsonpath="{..metadata.labels.mylabel}"'           'a a a a'
os::cmd::expect_success_and_text 'oc get -f ${TEST_DATA}/mixed-api-versions.yaml --output=jsonpath="{..metadata.annotations.myannotation}"' 'b b b b'
os::cmd::expect_success 'oc delete   -f ${TEST_DATA}/mixed-api-versions.yaml'
echo "list version conversion: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/basicresources/nodes"
os::cmd::expect_success 'oc get nodes'
(
  # subshell so we can unset kubeconfig
  cfg="${KUBECONFIG}"
  unset KUBECONFIG
  os::cmd::expect_success "kubectl get nodes --kubeconfig='${cfg}'"
)
echo "nodes: ok"
os::test::junit::declare_suite_end


os::test::junit::declare_suite_start "cmd/basicresources/create"
os::cmd::expect_success 'oc create dc my-nginx --image=nginx'
os::cmd::expect_success 'oc delete dc my-nginx'
os::cmd::expect_success 'oc create clusterquota limit-bob --project-label-selector=openshift.io/requester=user-bob --hard=pods=10'
os::cmd::expect_success 'oc delete clusterquota/limit-bob'
echo "create subcommands: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/basicresources/statefulsets"
os::cmd::expect_success 'oc create -f ${TEST_DATA}/statefulset.yaml'
os::cmd::try_until_success 'oc get pods testapp-0'
os::cmd::expect_success_and_text 'oc describe statefulset testapp' 'app=testapp'
os::cmd::expect_success 'oc delete -f ${TEST_DATA}/statefulset.yaml'
echo "statefulsets: ok"
os::test::junit::declare_suite_end


os::test::junit::declare_suite_start "cmd/basicresources/setprobe"
# Validate the probe command
arg="-f ${TEST_DATA}/hello-openshift/hello-pod.json"
os::cmd::expect_failure_and_text "oc set probe" "error: one or more resources"
os::cmd::expect_failure_and_text "oc set probe ${arg}" "error: you must specify"
os::cmd::expect_failure_and_text "oc set probe ${arg} --local -o yaml --liveness --get-url=https://127.0.0.1/path" "port must be specified as part of a url"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness" 'livenessProbe: \{\}'
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness --initial-delay-seconds=10" "livenessProbe:"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness --initial-delay-seconds=10" "initialDelaySeconds: 10"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness -- echo test" "livenessProbe:"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --readiness -- echo test" "readinessProbe:"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness -- echo test" "exec:"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness -- echo test" "\- echo"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness -- echo test" "\- test"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness --open-tcp=3306" "tcpSocket:"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness --open-tcp=3306" "port: 3306"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness --open-tcp=port" "port: port"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness --get-url=https://127.0.0.1:8080/path" "port: 8080"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness --get-url=https://127.0.0.1:8080/path" "path: /path"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness --get-url=https://127.0.0.1:8080/path" "scheme: HTTPS"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness --get-url=http://127.0.0.1:8080/path" "scheme: HTTP"
os::cmd::expect_success_and_text "oc set probe ${arg} --local -o yaml --liveness --get-url=https://127.0.0.1:8080/path" "host: 127.0.0.1"
os::cmd::expect_success "oc create -f ${TEST_DATA}/test-deployment-config.yaml"
os::cmd::expect_failure_and_text "oc set probe dc/test-deployment-config --liveness" "Required value: must specify a handler type"
os::cmd::expect_success_and_text "oc set probe dc test-deployment-config --liveness --open-tcp=8080" "updated"
os::cmd::expect_success_and_text "oc set probe dc/test-deployment-config --liveness --open-tcp=8080 --v=1" "was not changed"
os::cmd::expect_success_and_text "oc get dc/test-deployment-config -o yaml" "livenessProbe:"
os::cmd::expect_success_and_text "oc set probe dc/test-deployment-config --liveness --initial-delay-seconds=10" "updated"
os::cmd::expect_success_and_text "oc get dc/test-deployment-config -o yaml" "initialDelaySeconds: 10"
os::cmd::expect_success_and_text "oc set probe dc/test-deployment-config --liveness --initial-delay-seconds=20" "updated"
os::cmd::expect_success_and_text "oc get dc/test-deployment-config -o yaml" "initialDelaySeconds: 20"
os::cmd::expect_success_and_text "oc set probe dc/test-deployment-config --liveness --failure-threshold=2" "updated"
os::cmd::expect_success_and_text "oc get dc/test-deployment-config -o yaml" "initialDelaySeconds: 20"
os::cmd::expect_success_and_text "oc get dc/test-deployment-config -o yaml" "failureThreshold: 2"
os::cmd::expect_success_and_text "oc set probe dc/test-deployment-config --readiness --success-threshold=4 -- echo test" "updated"
os::cmd::expect_success_and_text "oc get dc/test-deployment-config -o yaml" "initialDelaySeconds: 20"
os::cmd::expect_success_and_text "oc get dc/test-deployment-config -o yaml" "successThreshold: 4"
os::cmd::expect_success_and_text "oc set probe dc test-deployment-config --liveness --period-seconds=5" "updated"
os::cmd::expect_success_and_text "oc get dc/test-deployment-config -o yaml" "periodSeconds: 5"
os::cmd::expect_success_and_text "oc set probe dc/test-deployment-config --liveness --timeout-seconds=6" "updated"
os::cmd::expect_success_and_text "oc get dc/test-deployment-config -o yaml" "timeoutSeconds: 6"
os::cmd::expect_success_and_text "oc set probe dc --all --liveness --timeout-seconds=7" "updated"
os::cmd::expect_success_and_text "oc get dc -o yaml" "timeoutSeconds: 7"
os::cmd::expect_success_and_text "oc set probe dc/test-deployment-config --liveness --remove" "updated"
os::cmd::expect_success_and_not_text "oc get dc/test-deployment-config -o yaml" "livenessProbe"
os::cmd::expect_success "oc delete dc/test-deployment-config"
echo "set probe: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/basicresources/setenv"
os::cmd::expect_success "oc create -f ${TEST_DATA}/test-deployment-config.yaml"
os::cmd::expect_success "oc create -f ${TEST_DATA}/test-buildcli.json"
os::cmd::expect_success_and_text "oc set env dc/test-deployment-config FOO=1st" "updated"
os::cmd::expect_success_and_text "oc set env dc/test-deployment-config FOO=2nd" "updated"
os::cmd::expect_success_and_text "oc set env dc/test-deployment-config FOO=bar --overwrite" "updated"
os::cmd::expect_failure_and_text "oc set env dc/test-deployment-config FOO=zee --overwrite=false" "already has a value"
os::cmd::expect_success_and_text "oc set env dc/test-deployment-config --list" "FOO=bar"
os::cmd::expect_success_and_text "oc set env dc/test-deployment-config FOO-" "updated"
os::cmd::expect_success_and_text "oc set env bc --all FOO=bar" "updated"
os::cmd::expect_success_and_text "oc set env bc --all --list" "FOO=bar"
os::cmd::expect_success_and_text "oc set env bc --all FOO-" "updated"
os::cmd::expect_success "oc create secret generic mysecret --from-literal='foo.bar=secret'"
os::cmd::expect_success_and_text "oc set env --from=secret/mysecret --prefix=PREFIX_ dc/test-deployment-config" "updated"
os::cmd::expect_success_and_text "oc set env dc/test-deployment-config --list" "PREFIX_FOO_BAR from secret mysecret, key foo.bar"
os::cmd::expect_success_and_text "oc set env dc/test-deployment-config --list --resolve" "PREFIX_FOO_BAR=secret"
os::cmd::expect_success "oc delete secret mysecret"
os::cmd::expect_failure_and_text "oc set env dc/test-deployment-config --list --resolve" "error retrieving reference for PREFIX_FOO_BAR"
# switch to view user to ensure view-only users can't get secrets through env var resolution
new="$(mktemp -d)/tempconfig"
os::cmd::expect_success "oc config view --raw > $new"
export KUBECONFIG=$new
project=$(oc project -q)
#os::cmd::expect_success 'oc policy add-role-to-user view view-user'
#os::cmd::expect_success 'oc login -u view-user -p anything'
#os::cmd::try_until_success 'oc project ${project}'
#os::cmd::expect_failure_and_text "oc set env dc/test-deployment-config --list --resolve" 'cannot get resource "secrets" in API group "" in the namespace'
#oc login -u system:admin
# clean up
os::cmd::expect_success "oc delete dc/test-deployment-config"
os::cmd::expect_success "oc delete bc/ruby-sample-build-validtag"
echo "set env: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/basicresources/expose"
# Expose service as a route
os::cmd::expect_success 'oc create -f ${TEST_DATA}/test-service.json'
os::cmd::expect_failure 'oc expose service frontend --create-external-load-balancer'
os::cmd::expect_failure 'oc expose service frontend --port=40 --type=NodePort'
os::cmd::expect_success 'oc expose service frontend --path=/test'
os::cmd::expect_success_and_text "oc get route.v1.route.openshift.io frontend --template='{{.spec.path}}'" "/test"
os::cmd::expect_success_and_text "oc get route.v1.route.openshift.io frontend --template='{{.spec.to.name}}'" "frontend"           # routes to correct service
os::cmd::expect_success_and_text "oc get route.v1.route.openshift.io frontend --template='{{.spec.port.targetPort}}'" ""
os::cmd::expect_success 'oc delete svc,route -l name=frontend'
# Test that external services are exposable
os::cmd::expect_success 'oc create -f ${TEST_DATA}/external-service.yaml'
os::cmd::expect_success 'oc expose svc/external'
os::cmd::expect_success_and_text 'oc get route external' 'external'
os::cmd::expect_success 'oc delete route external'
os::cmd::expect_success 'oc delete svc external'
# Expose multiport service and verify we set a port in the route
os::cmd::expect_success 'oc create -f ${TEST_DATA}/multiport-service.yaml'
os::cmd::expect_success 'oc expose svc/frontend --name route-with-set-port'
os::cmd::expect_success_and_text "oc get route route-with-set-port --template='{{.spec.port.targetPort}}'" "web"
echo "expose: ok"
os::test::junit::declare_suite_end

# Test OAuth access token describer
os::cmd::expect_success 'oc create -f ${TEST_DATA}/oauthaccesstoken.yaml'
os::cmd::expect_success_and_text "oc describe oauthaccesstoken sha256~efaca6fab897953ffcb4f857eb5cbf2cf3a4c33f1314b4922656303426b1cfc9" "efaca6fab897953ffcb4f857eb5cbf2cf3a4c33f1314b4922656303426b1cfc9"
echo "OAuth descriptor: ok"

os::cmd::expect_success 'oc delete all --all'

os::test::junit::declare_suite_start "cmd/basicresources/projectadmin"
# switch to test user to be sure that default project admin policy works properly
temp_config="$(mktemp -d)/tempconfig"
os::cmd::expect_success "oc config view --raw > '${temp_config}'"
export KUBECONFIG="${temp_config}"
#os::cmd::expect_success 'oc policy add-role-to-user admin project-admin'
#os::cmd::expect_success 'oc login -u project-admin -p anything'
#os::cmd::expect_success 'oc new-project test-project-admin'
#os::cmd::try_until_success "oc project test-project-admin"

os::cmd::expect_success 'oc create deploymentconfig --image=image-registry.openshift-image-registry.svc:5000/openshift/tools:latest test'
os::cmd::expect_success 'oc run --image=image-registry.openshift-image-registry.svc:5000/openshift/tools:latest --restart=Never test3'
os::cmd::expect_success 'oc create job --image=image-registry.openshift-image-registry.svc:5000/openshift/tools:latest test4'
os::cmd::expect_success 'oc delete dc/test pod/test3 job/test4'

os::cmd::expect_success_and_text 'oc create deploymentconfig --dry-run foo --image=bar -o name'               'deploymentconfig.apps.openshift.io/foo'
os::cmd::expect_success_and_text 'oc run --dry-run foo --image=bar -o name --restart=Never'                'pod/foo'
os::cmd::expect_success_and_text 'oc create job --dry-run foo --image=bar -o name'              'job.batch/foo'
os::cmd::expect_success_and_text 'oc create deploymentconfig --dry-run foo --image=bar -o name' 'deploymentconfig.apps.openshift.io/foo'
os::cmd::expect_success_and_text 'oc run --dry-run foo --image=bar -o name'          'pod/foo'

os::cmd::expect_success 'oc process -f ${TEST_DATA}/application-template-stibuild.json -l name=mytemplate | oc create -f -'
os::cmd::expect_success 'oc delete all -l name=mytemplate'
#os::cmd::expect_success 'oc new-app https://github.com/openshift/ruby-hello-world'
#os::cmd::expect_success 'oc get dc/ruby-hello-world'

#os::cmd::expect_success_and_text "oc get dc/ruby-hello-world --template='{{ .spec.replicas }}'" '1'
#patch='{"spec": {"replicas": 2}}'
#os::cmd::expect_success "oc patch dc/ruby-hello-world -p '${patch}'"
#os::cmd::expect_success_and_text "oc get dc/ruby-hello-world --template='{{ .spec.replicas }}'" '2'
#
#os::cmd::expect_success 'oc delete all -l app=ruby-hello-world'
#os::cmd::expect_failure 'oc get dc/ruby-hello-world'
echo "delete all: ok"
os::test::junit::declare_suite_end

# service accounts should not be allowed to request new projects
# TODO re-enable once we can use tokens instead of certs
#os::cmd::expect_failure_and_text "oc new-project --token='$( oc sa get-token builder )' will-fail" 'Error from server \(Forbidden\): You may not request a new project via this API.'

os::test::junit::declare_suite_start "cmd/basicresources/patch"
# Validate patching works correctly
#os::cmd::expect_success 'oc login -u system:admin'
group_json='{"kind":"Group","apiVersion":"v1","metadata":{"name":"patch-group"}}'
os::cmd::expect_success          "echo '${group_json}' | oc create -f -"
os::cmd::expect_success          "oc patch group patch-group -p 'users: [\"myuser\"]' --loglevel=8"
os::cmd::expect_success_and_text 'oc get group patch-group -o yaml' 'myuser'
os::cmd::expect_success          "oc patch group patch-group -p 'users: []' --loglevel=8"
# applying the same patch twice results in exit code 0, and "not patched" text
os::cmd::expect_success_and_text "oc patch group patch-group -p 'users: []'" "patched \(no change\)"
# applying an invalid patch results in exit code 1 and an error
os::cmd::expect_failure_and_text "oc patch group patch-group -p 'users: \"\"'" "cannot restore slice from string"
os::cmd::expect_success_and_text 'oc get group patch-group -o yaml' 'users: \[\]'
echo "patch: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_end
