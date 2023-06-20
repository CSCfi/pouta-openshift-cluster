from kubernetes import client, config
from openshift.dynamic import DynamicClient
import logging
from datetime import datetime
from openshift.dynamic.exceptions import NotFoundError


class RahtiClient(object):

    def __init__(self, name, project_grace_period=90, pvs_grace_period=30, kubeconfig_path=None, auth_parameters=None):

        if (kubeconfig_path is None) and (auth_parameters is None):
            raise ValueError("both authentication methods are set to None")

        self.name = name
        self.kubeconfig_path = kubeconfig_path
        self.auth_parameters = auth_parameters

        if self.kubeconfig_path is not None:
            self.k8s_client = config.new_client_from_config(self.kubeconfig_path)
        else:
            configuration = client.Configuration()
            configuration.host = self.auth_parameters["host"]
            configuration.api_key["authorization"] = self.auth_parameters["token"]
            configuration.api_key_prefix['authorization'] = "Bearer"
            self.k8s_client = client.api_client.ApiClient(configuration=configuration)

        self.dyn_client = DynamicClient(self.k8s_client)
        self.project_grace_period = project_grace_period
        self.pvs_grace_period = pvs_grace_period

    def suspend_project(self, csc_project_id):
        """
        Suspend one CSC project in the cluster.
        @param csc_project_id: the ID of CSC project to be suspended.
        @return: None.
        """
        v1_namespaces = self.dyn_client.resources.get(api_version='v1', kind='Namespace')
        v1_quotas = self.dyn_client.resources.get(api_version='v1', kind='ResourceQuota')
        v1_pods = self.dyn_client.resources.get(api_version='v1', kind='Pod')

        # Get namespaces associated with the CSC project to be suspended
        namespaces = v1_namespaces.get(label_selector='csc_project=' + csc_project_id)
        logging.info("Suspending %s namespaces for CSC project: %s in %s" % (len(namespaces.items), csc_project_id, self.name))

        for ns in namespaces.items:
            # Suspend only the not suspended namespaces
            if 'suspended' not in dict(ns.metadata.labels) or ns.metadata.labels.suspended != 'true':

                # Retrieve the Pods quota of the namespace
                ns_quota = v1_quotas.get(name='compute-resources', namespace=ns.metadata.name)
                # Set namespace pods quota to zero
                # Save original pods quota (before suspension)
                # If Pod quota already set 0 and there is an already saved original pods quota
                if ('annotations' in dict(ns_quota.metadata)) and \
                        ('original_pods_quota' in dict(ns_quota.metadata.annotations)) and \
                        (ns_quota.spec.hard.pods == '0'):
                    original_pods_quota = ns_quota.metadata.annotations.original_pods_quota
                else:  # set the original pods quota to the current hard pods quota
                    original_pods_quota = ns_quota.spec.hard.pods

                # Save original pods quota as annotations, set pods quota to 0.
                quota_patch_body = {
                    'metadata': {
                        'annotations': {
                            'original_pods_quota': original_pods_quota
                        },
                        'name': 'compute-resources'
                    },
                    'spec': {
                        'hard': {
                            'pods': '0'
                        }
                    }
                }
                v1_quotas.patch(body=quota_patch_body, namespace=ns.metadata.name)

                # Delete all pods
                try:
                    v1_pods.delete(field_selector='metadata.namespace=' + ns.metadata.name, namespace=ns.metadata.name)
                except TypeError:
                    # This exception is raised when there are No pods to be deleted.
                    pass

                # Mark namespace as suspended
                suspension_time = datetime.strftime(datetime.now(), '%d/%m/%y %H:%M:%S')
                #suspension_time = '10/07/22 13:38:21'
                ns_patch_body = {
                    'metadata': {
                        'annotations': {
                            'suspension_time': suspension_time
                        },
                        'labels': {
                            'suspended': 'true'
                        }
                    }
                }
                v1_namespaces.patch(body=ns_patch_body, name=ns.metadata.name)
                logging.info("     %s suspended" % ns.metadata.name)

            else:
                logging.info("     %s already suspended" % ns.metadata.name)

    def unsuspend_project(self, csc_project_id):
        """
        Unsuspend a suspended CSC project in Rahti
        @param csc_project_id: the ID of CSC project to be unsuspended.
        @return: None.
        """
        v1_namespaces = self.dyn_client.resources.get(api_version='v1', kind='Namespace')
        v1_quotas = self.dyn_client.resources.get(api_version='v1', kind='ResourceQuota')

        # Get the namespaces associated with the CSC project to be unsuspended
        namespaces = v1_namespaces.get(label_selector='csc_project=' + csc_project_id)
        logging.info("Unsuspending namespaces for CSC project: %s in %s" % (csc_project_id, self.name))
        for ns in namespaces.items:
            # Unsuspend only the namespaces already suspended
            if 'suspended' in dict(ns.metadata.labels) and ns.metadata.labels.suspended == 'true':
                # Retrieve the Pods quota of the namespace
                ns_quota = v1_quotas.get(name='compute-resources', namespace=ns.metadata.name)
                # Get the original pods quota of the namespace
                original_pods_quota = ns_quota.metadata.annotations.original_pods_quota
                # Set the pods quota to its original value
                quota_patch_body = {
                    'metadata': {
                        'annotations': {
                            'original_pods_quota': None
                        },
                        'name': 'compute-resources'
                    },
                    'spec': {
                        'hard': {
                            'pods': original_pods_quota
                        }
                    }
                }

                v1_quotas.patch(body=quota_patch_body, namespace=ns.metadata.name)

                # Mark a namespace as unsuspended
                ns_patch_body = {
                    'metadata': {
                        'annotations': {
                            'suspension_time': None
                        },
                        'labels': {
                            'suspended': 'false'
                        }
                    }
                }

                v1_namespaces.patch(body=ns_patch_body, name=ns.metadata.name)
                logging.info("     Namespace %s unsuspended" % ns.metadata.name)
            else:
                logging.info("     Namespace %s already unsuspended" % ns.metadata.name)

    def delete_project(self, csc_project_id):
        """
        Delete a suspended CSC project from Rahti.
        @param dyn_client: DynamicClient object used to interact with OpenShift API.
        @param csc_project_id: the ID of CSC project to be deleted.
        @return: 0 if deletion is successful, 1 otherwise.
        """
        v1_namespaces = self.dyn_client.resources.get(api_version='v1', kind='Namespace')
        v1_projects = self.dyn_client.resources.get(api_version='project.openshift.io/v1', kind='Project')
        v1_pvcs = self.dyn_client.resources.get(api_version='v1', kind='PersistentVolumeClaim')
        v1_pvs = self.dyn_client.resources.get(api_version='v1', kind='PersistentVolume')

        # Get namespaces associated with the CSC project to be deleted
        namespaces = v1_namespaces.get(label_selector='csc_project=' + csc_project_id)
        all_ns_deleted = True
        logging.info("Deleting %s namespaces for CSC project: %s in %s" % (len(namespaces.items), csc_project_id, self.name))

        for ns in namespaces.items:
            # Delete only the suspended namespaces
            if 'suspended' in dict(ns.metadata.labels) and ns.metadata.labels.suspended == 'true' and \
                    'suspension_time' in dict(ns.metadata.annotations):

                # Compute the elapsed time since the namespace was suspended
                suspension_time = datetime.strptime(ns.metadata.annotations.suspension_time, '%d/%m/%y %H:%M:%S')
                deletion_time = datetime.now()
                elapsed_time = deletion_time - suspension_time

                # Delete only the namespaces suspended for a period greater than PROJECT_GRACE_PERIOD days.
                if elapsed_time.days > self.project_grace_period:
                    # Get the list of PVCs in the namespace
                    pvcs = v1_pvcs.get(namespace=ns.metadata.name)
                    all_pvs_patched = True
                    # Change PVs reclaim policy to 'Retain' (to be able to delete the namespace
                    # and its PVCs without deleting the PVs)
                    for pvc in pvcs.items:
                        if pvc.status.phase == 'Bound':
                            # Patch the PV of the bound to the PVC:
                            #  - Change the reclaim policy to 'Retain'
                            #  - Add metadata labels to track the PV.
                            #  - Add a release timestamp.
                            release_time = datetime.strftime(datetime.now(), '%d/%m/%y %H:%M:%S')
                            #release_time = '10/07/22 13:38:21'

                            pv_patch_body = {
                                'metadata': {
                                    'name': pvc.spec.volumeName,

                                    'annotations': {
                                        'release_time': release_time
                                    },
                                    'labels': {
                                        'stale_pv': 'true',
                                        'csc_project': csc_project_id,
                                        'rahti_project': ns.metadata.name,
                                        'pvc_name': pvc.metadata.name
                                    }
                                },
                                'spec': {
                                    'persistentVolumeReclaimPolicy': 'Retain'
                                }
                            }
                            try:
                                v1_pvs.patch(body=pv_patch_body)
                            except Exception:
                                logging.error("Unable to change persistentVolumeReclaimPolicy of PV %s" %
                                              pvc.spec.volumeName)
                                all_pvs_patched = False

                    # Delete the namespace only if all its associated PVs were patched
                    if all_pvs_patched:
                        try:
                            # Delete the namespace/project.
                            v1_projects.delete(name=ns.metadata.name)
                            logging.info("     Rahti project %s deleted, suspended since %s days" %
                                         (ns.metadata.name, elapsed_time.days))
                        except Exception:
                            logging.error("     Unable to delete Rahti project %s" % ns.metadata.name)
                            all_ns_deleted = False
                    else:
                        logging.error("     Skipping Rahti project %s deletion because not all PVs were patched, " %
                                      ns.metadata.name)
                        all_ns_deleted = False
                else:
                    logging.info(
                        "      Skipping Rahti project %s deletion because it is in grace period, %s days remaining"
                        " , " % (ns.metadata.name, (self.project_grace_period - elapsed_time.days)))
                    all_ns_deleted = False
            else:
                logging.error(
                    "     Rahti project %s associated with CSC project %s is not suspended, please suspend before"
                    " deletion " % (ns.metadata.name, csc_project_id))
                all_ns_deleted = False

        # Return an error code if not all the namespaces were deleted.
        if all_ns_deleted:
            return 0
        else:
            return 1

    def clean_pvs(self):
        """
        Delete all stale persistent volumes in Rahti.
        """
        v1_projects = self.dyn_client.resources.get(api_version='project.openshift.io/v1', kind='Project')
        v1_pvs = self.dyn_client.resources.get(api_version='v1', kind='PersistentVolume')

        # Get the list of all stale PVs.
        pvs = v1_pvs.get(label_selector='stale_pv=true')

        for pv in pvs.items:
            # Make sure that the associated Rahti namespace was deleted
            try:
                pv_rahti_project_name = pv.metadata.labels.rahti_project
                v1_projects.get(name=pv_rahti_project_name)
                logging.error(
                    "     The project associated with  stale PV %s still exists, not deleting PV" % pv.metadata.name)
            # The associated Rahti project was effectively deleted.
            except NotFoundError:
                # Compute the elapsed time since the PV was released.
                release_time = datetime.strptime(pv.metadata.annotations.release_time, '%d/%m/%y %H:%M:%S')
                deletion_time = datetime.now()
                elapsed_time = deletion_time - release_time
                # Delete the PV only if it was released since at least PVS_GRACE_PERIOD days.
                if elapsed_time.days > self.pvs_grace_period:
                    # TO-DO: check PV is not stuck in Terminating state.
                    v1_pvs.delete(name=pv.metadata.name)
                    logging.info("     Stale PV %s deleted" % pv.metadata.name)
                else:
                    logging.info("     Stale PV %s not deleted, %s days remaining" %
                                 (pv.metadata.name, (self.pvs_grace_period - elapsed_time.days)))

    def get_project_namespaces(self, csc_project_id):
        """
        Return the list of namespaces associated with a given CSC project.
        @param csc_project_id: the ID of CSC project.
        @return: a list of namespaces.
        """

        v1_namespaces = self.dyn_client.resources.get(api_version='v1', kind='Namespace')
        # Get namespaces associated with the CSC project
        namespaces = v1_namespaces.get(label_selector='csc_project=' + csc_project_id)
        to_return = []
        for ns in namespaces.items:
            to_return.append(ns.metadata.name)
        return to_return




