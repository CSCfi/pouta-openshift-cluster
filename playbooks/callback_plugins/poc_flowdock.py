from ansible.plugins.callback import CallbackBase
import requests

FLOWDOCK_MSG_API_URL = 'https://api.flowdock.com/v1/messages/influx/'


def check_flowdock_config(func):
    def wrapper(*args, **kwargs):
        flowdock_configured = args[0].flowdock_configured
        if flowdock_configured:
            return func(*args, **kwargs)
        else:
            pass
    return wrapper


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'aggregate'
    CALLBACK_NAME = 'poc_flowdock'

    def send_msg(self, from_address, subject, content, tags=None, link=None, source='Ansible'):
        url = FLOWDOCK_MSG_API_URL + str(self.api_token)

        req_args = {
            'source': source,
            'from_address': from_address,
            'subject': subject,
            'content': content,
            'format': 'html'
        }

        if tags:
            req_args['tags'] = ','.join(tags)
        if link:
            req_args['link'] = link

        res = requests.post(url, data=req_args)

        if res.status_code == 500:
            raise Exception(res.content)
        elif res.status_code == 200:
            return True
        else:
            res.raise_for_status()

    def v2_playbook_on_play_start(self, play):
        all_vars = play.get_variable_manager().get_vars()
        localhost_hostvars = all_vars['hostvars']['localhost']
        self.play_name = play.name

        try:
            self.api_token = localhost_hostvars['flowdock_api_token']
            self.env_name = localhost_hostvars['cluster_display_name']
            self.email = localhost_hostvars['team_email']
            self.flowdock_configured = True
        except:
            self.flowdock_configured = False

        try:
            self.gitlab_pipelines_url = localhost_hostvars['gitlab_pipelines_url']
            self.gitlab_ci_commit_ref_name = localhost_hostvars['gitlab_ci_commit_ref_name']
            self.gitlab_ci_commit_sha = localhost_hostvars['gitlab_ci_commit_sha']
            self.gitlab_ci_pipeline_id = localhost_hostvars['gitlab_ci_pipeline_id']
            self.ci_job = True
        except:
            self.ci_job = False

    @check_flowdock_config
    def v2_playbook_on_stats(self, stats):
        tags = ['ansible']

        if stats.failures == {}:
            msg_subject = u'\U0001f600 Ansible success in {}'.format(self.env_name)
            tags.append('ansible_ok')
        else:
            msg_subject = u'\U0001f620 Ansible failure in {}'.format(self.env_name)
            tags.append('ansible_fail')

        msg = '<p>Ansible ran in {}</p>'.format(self.env_name)
        source = 'Ansible'
        pipeline_url = None

        if self.ci_job:
            pipeline_url = str(self.gitlab_pipelines_url) + '/' + str(self.gitlab_ci_pipeline_id)
            msg += '<ul>'
            msg += '<li><a href="{}">View pipeline in GitLab</a></li>'.format(pipeline_url)
            msg += '<li><b>Commit ref name: </b>{}</li>'.format(self.gitlab_ci_commit_ref_name)
            msg += '<li><b>Commit SHA: </b>{}</li>'.format(self.gitlab_ci_commit_sha)
            msg += '</ul>'
            tags.append('gitlab')
            tags.append(self.gitlab_ci_commit_ref_name)
            source = 'GitLab'

        self.send_msg(self.email,
                      msg_subject,
                      msg,
                      tags=tags,
                      link=pipeline_url,
                      source=source)
