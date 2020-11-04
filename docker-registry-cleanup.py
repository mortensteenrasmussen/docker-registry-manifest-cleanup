import glob
import urllib3
from requests.auth import HTTPBasicAuth
import requests
import json
import re
import os
import boto
from boto.s3.key import Key

############################
######## Functions #########
############################
def exit_with_error(message):
	print(message)
	print("Exiting")
	exit(1)

# Initial setup
try:
	if "DRY_RUN" in os.environ and os.environ['DRY_RUN'] == "true":
		dry_run_mode = True
		print("Running in dry-run mode. No changes will be made.")
		print()
	else:
		dry_run_mode = False
	if "REGISTRY_STORAGE" in os.environ and os.environ['REGISTRY_STORAGE'] == "S3":
		print("Running against S3 storage")
		storage_on_s3 = True
		s3_access_key = os.environ['ACCESS_KEY']
		s3_secret_key = os.environ['SECRET_KEY']
		s3_bucket = os.environ['BUCKET']
		s3_region = os.environ['REGION']
		if "REGISTRY_DIR" in os.environ:
			registry_dir = os.environ['REGISTRY_DIR']
		else:
			registry_dir = "/"
	else:
		print("Running against local storage")
		storage_on_s3 = False
		if "REGISTRY_DIR" in os.environ:
			registry_dir = os.environ['REGISTRY_DIR']
		else:
			registry_dir = "/registry"
	registry_url = os.environ['REGISTRY_URL']
except KeyError as e:
	exit_with_error("Missing environment variable: %s" % (e))

# Optional vars
if "REGISTRY_AUTH" in os.environ:
	registry_auth = HTTPBasicAuth(os.environ["REGISTRY_AUTH"].split(":")[0], os.environ["REGISTRY_AUTH"].split(":")[1])
else:
	registry_auth = {}
if "SELF_SIGNED_CERT" in os.environ:
	cert_verify = False
	urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
else:
	cert_verify = True

token_authentication = False
token_auth_details = {}
# Check connection to registry
try:
	r = requests.get("%s/v2/" % (registry_url), auth=registry_auth, verify=cert_verify)
	if r.status_code == 401:
		if "Www-Authenticate" in r.headers and "Bearer" in r.headers["Www-Authenticate"]:
			#We have token based auth, try it
			auth_header = r.headers["Www-Authenticate"].split(" ")[1]
			token_authentication = True
			token_auth_details = dict(s.split("=", 1) for s in re.sub('"',"",auth_header).split(","))
			r2 = requests.get("%s?service=%s&scope=" % (token_auth_details["realm"],token_auth_details["service"]), auth=registry_auth, verify=cert_verify)
			if r2.status_code == 401:
				exit_with_error("Got an authentication error connecting to the registry - even with token authentication. Check credentials, or add REGISTRY_AUTH='username:password'")
			else:
				auth_token = r2.json()["token"]
				registry_headers = {"Authorization": "Bearer %s" % (auth_token)}
		else:
			exit_with_error("Got an authentication error connecting to the registry. Check credentials, or add REGISTRY_AUTH='username:password'")
except requests.exceptions.SSLError as e:
	exit_with_error("Got an SSLError connecting to the registry. Might be a self signed cert, please set SELF_SIGNED_CERT=true")
except requests.exceptions.RequestException as e:
    exit_with_error("Could not contact registry at %s - error: %s" % (registry_url, e))

# Set variables
repo_dir = registry_dir + "/docker/registry/v2/repositories"
blob_dir = registry_dir + "/docker/registry/v2/blobs"
all_manifests = set()
linked_manifests = set()
linked_manifest_files = set()
file_list = set()
if storage_on_s3:
	
	bucket_size = 0

	# Connect to bucket
	conn = boto.s3.connect_to_region(s3_region, aws_access_key_id=s3_access_key, aws_secret_access_key=s3_secret_key)
	bucket = conn.get_bucket(s3_bucket)
	s3_file_list = bucket.list()

	#get all the filenames in bucket as well as size
	for key in s3_file_list:
		bucket_size += key.size
		file_list.add(key.name)
else:
	#local storage
	for filename in glob.iglob("%s/**" % (registry_dir), recursive=True):
		if os.path.isfile(filename):
			file_list.add(filename)

for filename in file_list:
	if filename.endswith("link"):
		if "_manifests/revisions/sha256" in filename:
			all_manifests.add(re.sub('.*docker/registry/v2/repositories/.*/_manifests/revisions/sha256/(.*)/link','\\1',filename))
		elif "_manifests/tags/" in filename and filename.endswith("/current/link"):
			linked_manifest_files.add(filename)

#fetch linked_manifest_files
for filename in linked_manifest_files:
	error = False
	if storage_on_s3:
		k = Key(bucket)
		k.key = filename

		#Get the shasum from the link file
		shasum = k.get_contents_as_string().decode().split(":")[1]

		#Get the manifest json to check if its a manifest list
		k.key = "%s/sha256/%s/%s/data" % (blob_dir, shasum[0:2], shasum)
		try:
			manifest = json.loads(k.get_contents_as_string().decode())
		except Exception as e:
			error = True
			print("Caught error trying to read manifest, ignoring.")

	else:
		shasum = open(filename, 'r').read().split(":")[1]
		try:
			manifest = json.loads(open("%s/sha256/%s/%s/data" % (blob_dir, shasum[0:2], shasum)).read())
		except Exception as e:
			error = True
			print("Caught error trying to read manifest, ignoring.")

	if not error:
		manifest_media_type = manifest["mediaType"]

		if manifest_media_type == "application/vnd.docker.distribution.manifest.list.v2+json":
			#add all manifests from manifest list
			for mf in manifest["manifests"]:
				linked_manifests.add(mf["digest"].split(":")[1])
	linked_manifests.add(shasum)

unused_manifests = all_manifests - linked_manifests

if len(unused_manifests) == 0:
	print("No manifests without tags found. Nothing to do.")
	if storage_on_s3:
		print("For reference, the size of the bucket is currently: %s bytes" % (bucket_size))
else:
	print("Found " + str(len(unused_manifests)) + " manifests without tags. Deleting")
	#counters
	current_count = 0
	cleaned_count = 0
	failed_count = 0
	total_count = len(unused_manifests)

	for manifest in unused_manifests:
		current_count += 1
		status_msg = "Cleaning %s of %s" % (current_count, total_count)
		if "DRY_RUN" in os.environ and os.environ['DRY_RUN'] == "true":
			status_msg += " ..not really, due to dry-run mode"
		print(status_msg)

		#get repos
		repos = set()
		for file in file_list:
			if "_manifests/revisions/sha256/%s" % (manifest) in file and file.endswith("link"):
				repos.add(re.sub(".*docker/registry/v2/repositories/(.*)/_manifests/revisions/sha256.*", "\\1", file))

		for repo in repos:
			if dry_run_mode:
				print("DRY_RUN: Would have run an HTTP DELETE request to %s/v2/%s/manifests/sha256:%s" % (registry_url, repo, manifest))
			else:
				if token_authentication:
					r2 = requests.get("%s?service=%s&scope=repository:%s:*" % (token_auth_details["realm"],token_auth_details["service"],repo), auth=registry_auth, verify=cert_verify)
					auth_token = r2.json()["token"]
					registry_headers = {"Authorization": "Bearer %s" % (auth_token)}
					r = requests.delete("%s/v2/%s/manifests/sha256:%s" % (registry_url, repo, manifest), verify=cert_verify, headers=registry_headers)
				else:
					r = requests.delete("%s/v2/%s/manifests/sha256:%s" % (registry_url, repo, manifest), auth=registry_auth, verify=cert_verify)

				if r.status_code == 202:
					cleaned_count += 1
				else:
					failed_count += 1
					print("Failed to clean manifest %s from repo %s with response code %s" % (manifest, repo, r.status_code))

	print("Job done, Cleaned %s of %s manifests." % (cleaned_count, total_count))
	print()
	print()
	if storage_on_s3:
		print("For reference, the size of the bucket before this run was: %s bytes" % (bucket_size))
	print()
	print("Please run a garbage-collect on the registry now to free up disk space.")
