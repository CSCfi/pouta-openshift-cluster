# Installer helper script
# https://github.com/openshift/installer/blob/master/docs/user/openstack/install_upi.md#master-ignition

for index in $(seq 0 2); do
    MASTER_HOSTNAME="$INFRA_ID-master-$index\n"
    python -c "import base64, json, sys
ignition = json.load(sys.stdin)
storage = ignition.get('storage', {})
files = storage.get('files', [])
files.append({'path': '/etc/hostname', 'mode': 420, 'contents': {'source': 'data:text/plain;charset=utf-8;base64,' + base64.standard_b64encode(b'$MASTER_HOSTNAME').decode().strip()}})
storage['files'] = files
ignition['storage'] = storage
json.dump(ignition, sys.stdout)" <master.ign >"$INFRA_ID-master-$index-ignition.json"
done
