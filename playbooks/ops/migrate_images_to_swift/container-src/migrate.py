"""
Author: Yacine Khettab <yacine.khettab@csc.fi>
Maintainer: CSC Rahti team <rahti-team@postit.csc.fi>
Company: CSC - IT Center for Science

Data migration script: copies files from a local directory over to a Swift
object storage container.

The aim for this script is to assist the migration of the docker integrated
registry storage backend from local PVCs to object storage (Swift).

The following environment variables are required:
 - The OpenStack credentials:
    - OS_AUTH_URL: keystone V2 authentication URL.
    - OS_USERNAME: username.
    - OS_PASSWORD: password.
    - OS_TENANT_NAME: OpenStack tenant.
    - OS_DOMAIN_NAME: OpenStack domain name (defaults to 'Default')
 - SRC_DATA_PATH: absolute path for local data path.
 - DST_DATA_PATH: folder path on the target Swift container.
 - SWIFT_CONTAINER_NAME: the name of the target Swift container.
"""

from swiftclient import Connection
from keystoneauth1.identity import v2
from keystoneauth1 import session
import os


os_auth_url = os.environ.get('OS_AUTH_URL')
os_username = os.environ.get('OS_USERNAME')
os_password = os.environ.get('OS_PASSWORD')
os_project_name = os.environ.get('OS_TENANT_NAME')
os_domain_name = os.environ.get('OS_DOMAIN_NAME', 'Default')
src_data_path = os.environ.get('SRC_DATA_PATH', '/registry')
destination_path = os.environ.get('DST_DATA_PATH', 'files')
swift_container_name = os.environ.get('SWIFT_CONTAINER_NAME')

# create a password auth plugin
auth = v2.Password(auth_url=os_auth_url,
                   username=os_username,
                   password=os_password,
                   tenant_name=os_project_name)

# create a Swift client Connection
keystone_session = session.Session(auth=auth)
swift = Connection(session=keystone_session)

# create a Swift container if the target one does not exist
swift.put_container(swift_container_name)

# copy all the data to object storage
print "Start copying local data"
for root, directories, filenames in os.walk(src_data_path):
    for filename in filenames:
        abs_filename = os.path.join(root,filename)

        print "copying: " + abs_filename

        with open(abs_filename, 'r') as file:
            swift.put_object(
                swift_container_name,
                abs_filename.replace(src_data_path, destination_path, 1),
                contents=file
            )
