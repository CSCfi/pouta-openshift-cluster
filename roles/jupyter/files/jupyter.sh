#!/bin/bash
source /etc/profile.d/virtualenvwrapper.sh
mkvirtualenv jupyter --system-site-packages
workon jupyter
pip install --upgrade setuptools pip
pip install jupyter
pip install findspark
