from ansible.plugins.callback import CallbackBase
import flowdock

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

  def v2_playbook_on_play_start(self, play):
    all_vars = play.get_variable_manager().get_vars()
    localhost_hostvars = all_vars['hostvars']['localhost']
    self.play_name = play.name

    try:
      self.api_token = localhost_hostvars['flowdock_api_token']
      self.env_name = localhost_hostvars['cluster_display_name']
      self.email = localhost_hostvars['team_email']
      self.fdclient = flowdock.FlowDock(api_key=self.api_token, app_name='Ansible')
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
    if stats.failures == {}:
      msg_subject = u'\U0001f600 Ansible success in {}'.format(self.env_name)
    else:
      msg_subject = u'\U0001f620 Ansible failure in {}'.format(self.env_name)

    msg = '<p>Ansible ran in {}</p>'.format(self.env_name)

    if self.ci_job:
      pipeline_url = str(self.gitlab_pipelines_url) + '/' + str(self.gitlab_ci_pipeline_id)
      msg += '<ul>'
      msg += '<li><a href="{}">View pipeline in GitLab</a></li>'.format(pipeline_url)
      msg += '<li><b>Commit ref name: </b>{}</li>'.format(self.gitlab_ci_commit_ref_name)
      msg += '<li><b>Commit SHA: </b>{}</li>'.format(self.gitlab_ci_commit_sha)
      msg += '</ul>'

    self.fdclient.post(self.email, msg_subject, msg)
