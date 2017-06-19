import os

import bottle


@bottle.route('/')
@bottle.jinja2_view('index.html.j2')
def server_static():
    bottle.TEMPLATES.clear()
    keys = ['platform_name', 'platform_api_url', 'platform_app_base_name']
    res = dict()
    for key in keys:
        if os.environ.get(key.upper()):
            print('setting key {}'.format(key))
            res[key] = os.environ.get(key.upper())

    return res


@bottle.route('/healthz')
def health():
    return 'OK!'


bottle.run(host='0.0.0.0', port=8080)
