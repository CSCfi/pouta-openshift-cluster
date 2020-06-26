import os
import sys
import syslog
import argparse
import pprint

from keystoneauth1 import session
from keystoneauth1.identity import v3
from keystoneclient.v3 import client as keystoneclient_v3
from novaclient import client
from cinderclient import client as cclient

class OpenStackDataStorage():

    def __init__(self):
        keystone_session = session.Session(auth=v3.Password(**self.getGredentials()))
        self.keystone_v3 = keystoneclient_v3.Client(session=keystone_session)
        nova = client.Client("2.1", session=keystone_session)
        self.all_servers = nova.servers.list()

        cinder = cclient.Client("3", session=keystone_session)
        self.all_volumes = cinder.volumes.list()

    def getGredentials(self):
        """
        Load login information from environment

        :returns: credentials
        :rtype: dict
        """
        cred = dict()
        cred['auth_url'] = os.environ.get('OS_AUTH_URL').replace("v2.0", "v3")
        cred['username'] = os.environ.get('OS_USERNAME')
        cred['password'] = os.environ.get('OS_PASSWORD')
        if 'OS_PROJECT_ID' in os.environ:
            cred['project_id'] = os.environ.get('OS_PROJECT_ID')
        if 'OS_TENANT_ID' in os.environ:
            cred['project_id'] = os.environ.get('OS_TENANT_ID')
        cred['user_domain_name'] = os.environ.get('OS_USER_DOMAIN_NAME', 'default')
        for key in cred:
            if not cred[key]:
                print('Credentials not loaded to environment: did you load the rc file?')
                exit(1)
        return cred

def main(argv=None):
    data = OpenStackDataStorage()
    all_volumes_per_nova = {}
    all_volumes_per_cinder = {}

    missing_from_nova = []
    missing_from_cinder = []
    volume_errors = []
    retcode = 0

    for volume in data.all_volumes:
        if volume._info['status'] == 'error':
            volume_errors.append(volume._info['id'])

    for server in data.all_servers:
        if len(server._info['os-extended-volumes:volumes_attached']) > 0:
            svols = [vol['id']  for vol in server._info['os-extended-volumes:volumes_attached']]
            all_volumes_per_nova[server._info['id']] = svols

    for volume in data.all_volumes:
        if len(volume._info["attachments"]) > 0:
            for attachment in volume._info["attachments"]:
                currvols = all_volumes_per_cinder.get(attachment['server_id'], [])
                currvols.append(attachment['volume_id'])
                all_volumes_per_cinder[attachment['server_id']] = currvols

    for key in all_volumes_per_nova.keys():
        if key in all_volumes_per_cinder:
            for vol in all_volumes_per_nova[key]:
                if vol not in all_volumes_per_cinder[key]:
                    missing_from_cinder.append(vol)
        else:
            missing_from_cinder.extend(all_volumes_per_nova[key])

    for key in all_volumes_per_cinder.keys():
        if key in all_volumes_per_nova:
            for vol in all_volumes_per_cinder[key]:
                if vol not in all_volumes_per_nova[key]:
                    missing_from_nova.append(vol)
        else:
            missing_from_nova.extend(all_volumes_per_cinder[key])

    if len(missing_from_nova) == 0 and len(missing_from_cinder) == 0 and len(volume_errors) == 0:
        print( "Volumes OK")
    else:
        print("Missing from nova: %s Missing from cinder: %s Volumes in error state %s:"  % (str(missing_from_nova), str(missing_from_cinder), str(error_volumes)))
        retcode = 2

    exit(retcode)

if __name__ == "__main__":
    main()
