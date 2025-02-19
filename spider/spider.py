"""
Provides the spider functionality (website checks).
"""

import argparse
import json
import logging
import re
import statistics
import time
from datetime import datetime
from pprint import pprint

from google.api_core.exceptions import InvalidArgument
from google.cloud import datastore

import checks
import config
import manager
import rating

def check_and_rate_site(entry):
    """
    Performs our site checks, calculates the score
    and returns results as a dict.
    """

    # all the info we'll return for the site
    result = {
        # input_url: The URL we derived all checks from
        'input_url': entry['url'],
        # Meta: Regional and type metadata for the site
        'meta': {
            'type': entry.get('type'),
            'level': entry.get('level'),
            'state': entry.get('state'),
            'district': entry.get('district'),
            'city': entry.get('city'),
        },
        # checks: Results from our checks
        'checks': {},
        # The actual report scoring criteria
        'rating': {},
        # resulting score
        'score': 0.0,
    }

    # Results from our next generation checkers
    result['checks'] = checks.perform_checks(entry['url'])

    result['rating'] = rating.calculate_rating(result['checks'])

    # Overall score is the sum of the individual scores
    for key in result['rating']:
        result['score'] += result['rating'][key]['score']

    # Remove bigger result portions to safe some storage:
    # - HTML page content
    # - Hyperlinks
    # - Performnance log
    try:
        for url in result['checks']['page_content']:
            del result['checks']['page_content'][url]['content']

        for url in result['checks']['load_in_browser']:
            del result['checks']['load_in_browser'][url]['performance_log']

        del result['checks']['hyperlinks']
    except:
        pass

    return result


def test_url(url):
    """
    Run the spider for a single URL and print the result.
    Doesn't write anything to the database.
    """
    logging.info("Crawling URL %s", url)

    # mock job
    job = {
        "url": url,
    }

    result = check_and_rate_site(entry=job)
    pprint(result)


def execute_single_job(datastore_client, job, entity_kind):
    """
    Executes spider for one single job
    """
    validate_job(job)

    logging.info("Starting job %s", job["url"])
    result = check_and_rate_site(entry=job)

    logging.debug("Full JSON representation of returned result: %s", json.dumps(result, default=str))

    logging.info("Job %s finished checks", job["url"])
    logging.info("Job %s writing to DB", job["url"])

    key = datastore_client.key(entity_kind, job["url"])
    entity = datastore.Entity(key=key)
    record = {
        'created': datetime.utcnow(),
        'meta': result['meta'],
        'checks': result['checks'],
        'rating': result['rating'],
        'score': result['score'],
    }

    entity.update(record)
    try:
        datastore_client.put(entity)
        logging.debug("Successfully wrote record to database")
    except InvalidArgument as ex:
        logging.error("Could not write result: %s", ex)
    except Exception as ex:
        logging.error("Could not write result: %s", ex)

def work_of_queue(datastore_client, entity_kind):
    """
    Take job from queue and finish it until there are no more jobs
    """
    while True:
        job = manager.get_job_from_queue(datastore_client)
        if job is None:
            logging.info("No more jobs. Exiting.")
            break

        execute_single_job(datastore_client, job, entity_kind)

def validate_job(jobdict):
    if "url" not in jobdict:
        raise Exception("Job does not have required 'url' attribute")
