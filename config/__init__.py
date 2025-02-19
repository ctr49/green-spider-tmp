

# connection timeout for website checks (seconds)
CONNECT_TIMEOUT = 5

# response timeout for website checks
READ_TIMEOUT = 10

# Git repo for our data
GREEN_DIRECTORY_REPO = 'https://git.verdigado.com/NB-Public/green-directory.git'

# folder in that repo that holds the data
GREEN_DIRECTORY_DATA_PATH = 'data/countries/de'

# folder we use locally to clone the repo
GREEN_DIRECTORY_LOCAL_PATH = './cache/green-directory'

# IP address of the verdigado GCMS server
GCMS_IP = "194.29.234.123"

# kind name of the spider job key datastore entities
JOB_DATASTORE_KIND = 'spider-jobs'

K8S_JOBS_PATH = './k8s-jobs'
K8S_JOB_TEMPLATE = './manager/job_template.yaml'
K8S_JOB_BATCH_SIZE = 10
