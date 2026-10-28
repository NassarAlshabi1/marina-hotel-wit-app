#!/usr/bin/env python3
"""Add the optional entryDate string attribute to Appwrite guest_infos.

This script changes the collection schema only; it never reads or updates guest
 documents. By default it is read-only. Pass --apply to create the one attribute
if it is missing. Existing compatible attributes are skipped.

Usage:
  APPWRITE_API_KEY=... python3 add_guest_entrydate_attribute.py
  APPWRITE_API_KEY=... python3 add_guest_entrydate_attribute.py --apply
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

ENDPOINT = os.environ.get("APPWRITE_ENDPOINT", "https://fra.cloud.appwrite.io/v1").rstrip("/")
PROJECT_ID = os.environ.get("APPWRITE_PROJECT_ID", "6a4408f300217885fd7b")
DATABASE_ID = os.environ.get("APPWRITE_DATABASE_ID", "6a4409b50019dd39dde5")
COLLECTION_ID = "guest_infos"
ATTRIBUTE_KEY = "entryDate"
ATTRIBUTE_TYPE = "string"
ATTRIBUTE_SIZE = 10
ATTRIBUTE_REQUIRED = False
REQUEST_TIMEOUT_SECONDS = 30
POLL_INTERVAL_SECONDS = 2
POLL_TIMEOUT_SECONDS = 120


class AppwriteApiError(RuntimeError):
    def __init__(self, status: int, error_type: str, message: str) -> None:
        super().__init__(message or error_type or f"HTTP {status}")
        self.status = status
        self.error_type = error_type


def _attributes_path() -> str:
    database = quote(DATABASE_ID, safe="")
    collection = quote(COLLECTION_ID, safe="")
    # Query.limit(100), serialized in the Appwrite REST query format.
    limit_query = json.dumps({"method": "limit", "values": [100]}, separators=(",", ":"))
    query_string = urlencode([("queries[]", limit_query)])
    return f"/databases/{database}/collections/{collection}/attributes?{query_string}"


def _request_json(method: str, path: str, api_key: str, body: dict | None = None) -> dict:
    url = f"{ENDPOINT}{path}"
    headers = {
        "X-Appwrite-Project": PROJECT_ID,
        "X-Appwrite-Key": api_key,
        "Accept": "application/json",
    }
    payload = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        payload = json.dumps(body).encode("utf-8")

    request = Request(url, data=payload, headers=headers, method=method)
    try:
        with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            raw = response.read()
    except HTTPError as error:
        try:
            error_payload = json.loads(error.read().decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            error_payload = {}
        raise AppwriteApiError(
            error.code,
            str(error_payload.get("type", "")),
            str(error_payload.get("message", "")),
        ) from None
    except (URLError, TimeoutError) as error:
        raise RuntimeError(f"Appwrite request failed ({type(error).__name__}).") from None

    if not raw:
        return {}
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError("Appwrite returned a non-JSON response.") from error


def list_attributes(api_key: str) -> list[dict]:
    response = _request_json("GET", _attributes_path(), api_key)
    attributes = response.get("attributes")
    if not isinstance(attributes, list):
        raise RuntimeError("Unexpected Appwrite response: missing attributes list.")
    return attributes


def find_entry_date_attribute(api_key: str) -> dict | None:
    for attribute in list_attributes(api_key):
        if attribute.get("key") == ATTRIBUTE_KEY:
            return attribute
    return None


def validate_existing_attribute(attribute: dict) -> None:
    actual = (attribute.get("type"), attribute.get("size"), attribute.get("required"))
    expected = (ATTRIBUTE_TYPE, ATTRIBUTE_SIZE, ATTRIBUTE_REQUIRED)
    if actual != expected:
        raise RuntimeError(
            "entryDate already exists, but its schema does not match the requested "
            "optional string (size 10). No changes were made."
        )


def wait_until_available(api_key: str) -> dict:
    deadline = time.monotonic() + POLL_TIMEOUT_SECONDS
    while True:
        attribute = find_entry_date_attribute(api_key)
        if attribute is not None:
            validate_existing_attribute(attribute)
            status = attribute.get("status")
            if status == "available":
                return attribute
            if status in ("stuck", "failed"):
                raise RuntimeError(f"Appwrite attribute reached status '{status}'.")
        else:
            status = "not visible yet"

        if time.monotonic() >= deadline:
            raise TimeoutError(
                f"Timed out waiting for {ATTRIBUTE_KEY} to become available; last status: {status}."
            )
        print(f"Waiting for {ATTRIBUTE_KEY} attribute: status={status} ...")
        time.sleep(POLL_INTERVAL_SECONDS)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Add only the optional entryDate string attribute to Appwrite "
            "guest_infos. Default mode is read-only."
        )
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="create the attribute if missing; without this flag, do a read-only preview",
    )
    args = parser.parse_args()

    api_key = os.environ.get("APPWRITE_API_KEY")
    if not api_key:
        print("ERROR: Set APPWRITE_API_KEY in the environment; the key is never prompted or printed.", file=sys.stderr)
        return 2
    if not ENDPOINT.startswith("https://"):
        print("ERROR: APPWRITE_ENDPOINT must use HTTPS.", file=sys.stderr)
        return 2

    print(f"Endpoint:   {ENDPOINT}")
    print(f"Project:    {PROJECT_ID}")
    print(f"Database:   {DATABASE_ID}")
    print(f"Collection: {COLLECTION_ID}")
    print(f"Attribute:  {ATTRIBUTE_KEY} ({ATTRIBUTE_TYPE}, size={ATTRIBUTE_SIZE}, required=false)")
    print("Scope:      schema only; no guest documents will be read or updated")

    # Confirm the target collection exists before considering any schema change.
    database = quote(DATABASE_ID, safe="")
    collection = quote(COLLECTION_ID, safe="")
    _request_json(
        "GET",
        f"/databases/{database}/collections/{collection}",
        api_key,
    )

    existing = find_entry_date_attribute(api_key)
    if existing is not None:
        validate_existing_attribute(existing)
        status = existing.get("status")
        if status == "available":
            print("SKIP: entryDate already exists with the expected schema; no change made.")
            return 0
        if not args.apply:
            print(f"READ-ONLY: entryDate already exists; current status={status}. No change made.")
            return 0
        available = wait_until_available(api_key)
        print(f"OK: existing entryDate is now available (status={available.get('status')}); no schema change made.")
        return 0

    if not args.apply:
        print("DRY RUN: entryDate is missing. Re-run with --apply to add only this attribute.")
        return 0

    create_path = f"/databases/{database}/collections/{collection}/attributes/string"
    body = {
        "key": ATTRIBUTE_KEY,
        "size": ATTRIBUTE_SIZE,
        "required": ATTRIBUTE_REQUIRED,
    }
    try:
        _request_json("POST", create_path, api_key, body)
        print("CREATED: Appwrite accepted the entryDate attribute request.")
    except AppwriteApiError as error:
        # If another run created it between the initial read and POST, treat that
        # as idempotent only after re-reading and validating the actual schema.
        if error.status != 409:
            raise
        current = find_entry_date_attribute(api_key)
        if current is None:
            raise RuntimeError("Appwrite returned 409, but entryDate is not visible in the schema.") from error
        validate_existing_attribute(current)
        print("SKIP: entryDate was created by another run; verifying its status.")

    available = wait_until_available(api_key)
    print(f"OK: entryDate is available (type={available.get('type')}, size={available.get('size')}, required={available.get('required')}).")
    print("No guest documents were changed. Run the in-app backfill separately to populate existing records.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AppwriteApiError as error:
        if error.status in (401, 403):
            print(
                f"ERROR: Appwrite denied the request (HTTP {error.status}, {error.error_type or 'permission error'}). "
                "Check the API key scopes; no secret was printed.",
                file=sys.stderr,
            )
        else:
            print(
                f"ERROR: Appwrite returned HTTP {error.status} ({error.error_type or 'API error'}). "
                "No secret was printed.",
                file=sys.stderr,
            )
        raise SystemExit(1)
    except (RuntimeError, TimeoutError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
