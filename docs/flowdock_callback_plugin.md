# Flowdock callback plugin

There is a callback plugin included with this repo that is used for notifying
Flowdock about successful and unsuccessful Ansible runs. You can find the source
code for the plugin under `playbooks/callback_plugins/poc_flowdock.py`.

## Minimal configuration

Certain variables need to be set for the callback plugin to do anything. If
these variables are not set, it will not send notifications.

| Variable             | Description                                                                                                                 |
|----------------------|-----------------------------------------------------------------------------------------------------------------------------|
| flowdock_api_token   | The API token for the flow that you would like to notify.You can get this from Flowdock's account page under "API tokens".  |
| cluster_display_name | The display name of the cluster for the subject of the notification so you can tell where a notification came from.         |
| team_email           | The email address to attach to the notification (required by the Flowdock API).                                             |

With these settings configured, you get a very minimal notification about
whether a playbook run succeeded or failed and the name of the cluster.

In addition to this, the callback plugin also needs to be added to the callback
whitelist in ansible.cfg. The ansible.cfg file included with this repository has
this plugin whitelisted out of the box.

## GitLab CI/CD context configuration

To make the notifications useful, additional context from a GitLab CI/CD
pipeline can also be displayed. Except for the pipeline URL, these variables can
be fed to Ansible at runtime in .gitlab-ci.yml using GitLab's builtin pipeline
variables. You can see how this can be done in the .gitlab-ci.yml file in this
repository.

These are the variables that need to be set:

| Variable                  | Description                                                                            |
|---------------------------|----------------------------------------------------------------------------------------|
| gitlab_pipelines_url      | The URL of the pipelines page for your project in GitLab (without a slash at the end). |
| gitlab_ci_commit_ref_name | The name of the feature branch used in the pipeline.                                   |
| gitlab_ci_commit_sha      | The SHA-1 commit id of the commit in the pipeline.                                     |
| gitlab_ci_pipeline_id     | The id of the pipeline in GitLab.                                                      |

## Helpful links for developing callback plugins

- This blog post was useful as a quick start to callback plugins: [Creating an
  Alerting Callback Plugin in Ansible - Part
  I](https://dev.to/jrop/creating-an-alerting-callback-plugin-in-ansible---part-i-1h0n)
- [Official Ansible documentation on callback
  plugins](https://docs.ansible.com/ansible/latest/dev_guide/developing_plugins.html#callback-plugins)
