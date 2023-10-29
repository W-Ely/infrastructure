import argparse
import hashlib
import json
import os
import os.path
import subprocess
import sys
from datetime import datetime, timezone

import boto3

CACHE_DIR = os.path.join(os.path.expanduser("~"), ".aws/assume-role/cache")


def is_expired(payload):
    expiration = payload.get("Credentials", {}).get("Expiration")
    if not expiration:
        return True
    expiration = datetime.strptime(expiration, "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=timezone.utc
    )
    now = datetime.now(timezone.utc)
    time_to_expiration = expiration - now
    time_to_expiration_seconds = (
        time_to_expiration.days * 24 * 60 * 60 + time_to_expiration.seconds
    )
    extra_seconds_as_buffer = 30
    return time_to_expiration_seconds < extra_seconds_as_buffer


def filename(kwargs):
    return (
        hashlib.sha1(
            f'{kwargs["RoleArn"]}{kwargs.get("SerialNumber")}'.encode("utf-8")
        ).hexdigest()
        + ".json"
    )


class Cache:
    def __init__(self, cache_dir=CACHE_DIR):
        if not os.path.isdir(cache_dir):
            os.makedirs(cache_dir, mode=0o755)
        self.cache_dir = cache_dir

    def get(self, kwargs):
        path = os.path.join(self.cache_dir, filename(kwargs))
        res = None
        try:
            with open(path, encoding="utf-8") as f:
                res = json.load(f)
        except (
            FileNotFoundError,
            PermissionError,
            IsADirectoryError,
            json.decoder.JSONDecodeError
        ):
            return None
        if is_expired(res):
            os.remove(path)
            return None
        return res

    def set(self, kwargs, res):
        path = os.path.join(self.cache_dir, filename(kwargs))
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
        res["Credentials"]["Expiration"] = (
            res["Credentials"]["Expiration"].strftime("%Y-%m-%dT%H:%M:%S") + "Z"
        )
        with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT, 0o600), "w") as f:
            f.write(json.dumps(res))


def main(args):
    sts_client = boto3.session.Session().client("sts")
    caller_identity = sts_client.get_caller_identity()
    arn = caller_identity["Arn"]
    arn_split = arn.split(":")
    args.account_id, identity = arn_split[4], arn_split[5]

    assume_role_kwargs = {
        "RoleArn": f"arn:aws:iam::{args.account_id}:role/{args.role}",
        "RoleSessionName": identity.replace("/", "-"),
    }
    if args.mfa:
        username = identity.split("/")[-1]
        mfa_serial = f"arn:aws:iam::{args.account_id}:mfa/{username}"
        assume_role_kwargs["SerialNumber"] = mfa_serial
    if args.duration:
        assume_role_kwargs["DurationSeconds"] = args.duration

    cache = Cache()
    res = cache.get(assume_role_kwargs)
    if res is None:
        if assume_role_kwargs["SerialNumber"]:
            sys.stderr.write("Enter MFA code: ")
            token = input()
            assume_role_kwargs["TokenCode"] = token
        res = sts_client.assume_role(**assume_role_kwargs)
        cache.set(assume_role_kwargs, res)
    aws_env = {
        "AWS_ACCESS_KEY_ID": res["Credentials"]["AccessKeyId"],
        "AWS_SECRET_ACCESS_KEY": res["Credentials"]["SecretAccessKey"],
        "AWS_SESSION_TOKEN": res["Credentials"]["SessionToken"],
    }
    env = os.environ.copy()
    env.update(aws_env)
    if "AWS_PROFILE" in env:
        del env["AWS_PROFILE"]
    process = subprocess.run(args.command, env=env, check=True)
    sys.exit(process.returncode)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--role", required=True, help="Role to assume.")
    parser.add_argument(
        "--mfa", default=False, action="store_true", help="Is MFA required"
    )
    parser.add_argument(
        "--duration", type=int, help="Duration of credentials in seconds"
    )
    parser.add_argument(
        "command", nargs=argparse.REMAINDER, help="The command to execute."
    )
    parsed_args = parser.parse_args()
    main(parsed_args)
