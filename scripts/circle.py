import http.client
import json
import os

CIRCLE_API_TOKEN = os.getenv("CIRCLE_API_TOKEN")
OWNER_SLUG = os.getenv("OWNER_SLUG")
BASE_HEADERS = {"Circle-Token": CIRCLE_API_TOKEN}
CONN = http.client.HTTPSConnection("circleci.com")


def list_contexts():
    slug = "gh/Hall-of-Mirrors"
    CONN.request(
        "GET",
        f"/api/v2/context?owner-slug={slug}&owner-type=organization",
        headers=BASE_HEADERS
    )
    return json.loads(CONN.getresponse().read().decode("utf-8"))


def create_context(context_name):
    payload = {
        "name": context_name,
        "owner":{
            "slug": OWNER_SLUG,
            "type":"organization",
        }
    }
    headers = {"content-type": "application/json", **BASE_HEADERS}
    CONN.request("POST", "/api/v2/context", json.dumps(payload), headers)
    return json.loads(CONN.getresponse().read().decode("utf-8"))


def update_context(name, key, value):
    contexts = list_contexts()["items"]
    for context in contexts:
        context_id = context["id"]
        if context["name"] == name:
            break
    payload = {"value": value}
    headers = {
        "content-type": "application/json",
        **BASE_HEADERS
        }
    CONN.request(
        "PUT",
        f"/api/v2/context/{context_id}/environment-variable/{key}",
        json.dumps(payload),
        headers
    )
    return json.loads(CONN.getresponse().read().decode("utf-8"))
