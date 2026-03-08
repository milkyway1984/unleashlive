#!/usr/bin/env python3
"""
Unleash live Assessment – Automated Test Script
================================================
1. Authenticates with Cognito (us-east-1) to retrieve a JWT
2. Concurrently calls /greet in us-east-1 AND eu-west-1
3. Concurrently calls /dispatch in us-east-1 AND eu-west-1
4. Asserts that each response's region matches the expected region
5. Prints latency measurements to demonstrate geographic performance difference

Usage:
    pip install boto3 requests
    python scripts/test_deployment.py \
        --user-pool-id     us-east-1_XXXXXXXXX \
        --client-id        XXXXXXXXXXXXXXXXXXXXXXXXXX \
        --username         your_email@example.com \
        --password         YourPassword123! \
        --api-us           https://XXXXXXXX.execute-api.us-east-1.amazonaws.com \
        --api-eu           https://XXXXXXXX.execute-api.eu-west-1.amazonaws.com

    Or set environment variables:
        COGNITO_USER_POOL_ID, COGNITO_CLIENT_ID,
        COGNITO_USERNAME, COGNITO_PASSWORD,
        API_ENDPOINT_US, API_ENDPOINT_EU
"""

import argparse
import concurrent.futures
import json
import os
import sys
import time

import boto3
import requests
from botocore.exceptions import ClientError

# ── ANSI colours ──────────────────────────────────────────────────────────────
GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

PASS = f"{GREEN}✓ PASS{RESET}"
FAIL = f"{RED}✗ FAIL{RESET}"


# ── Cognito authentication ────────────────────────────────────────────────────

def get_jwt(user_pool_id: str, client_id: str, username: str, password: str) -> str:
    """Authenticate with Cognito USER_PASSWORD_AUTH and return the IdToken."""
    print(f"\n{BOLD}── Step 1: Cognito Authentication ──────────────────────────────{RESET}")
    print(f"  User Pool : {user_pool_id}")
    print(f"  Username  : {username}")

    client = boto3.client("cognito-idp", region_name="us-east-1")
    try:
        resp = client.initiate_auth(
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={"USERNAME": username, "PASSWORD": password},
            ClientId=client_id,
        )
    except ClientError as e:
        print(f"{RED}  Cognito auth failed: {e}{RESET}")
        sys.exit(1)

    id_token = resp["AuthenticationResult"]["IdToken"]
    expires  = resp["AuthenticationResult"]["ExpiresIn"]
    print(f"  {PASS}  JWT obtained (expires in {expires}s)")
    return id_token


# ── HTTP helper ───────────────────────────────────────────────────────────────

def call_endpoint(label: str, url: str, token: str, method: str = "GET") -> dict:
    """Call an API endpoint with a Bearer token; return result dict with latency."""
    headers = {"Authorization": f"Bearer {token}"}
    start   = time.monotonic()
    try:
        if method.upper() == "POST":
            r = requests.post(url, headers=headers, timeout=30)
        else:
            r = requests.get(url, headers=headers, timeout=30)
        latency_ms = (time.monotonic() - start) * 1000
        body = {}
        try:
            body = r.json()
        except Exception:
            body = {"raw": r.text}
        return {
            "label":      label,
            "url":        url,
            "status":     r.status_code,
            "latency_ms": latency_ms,
            "body":       body,
            "ok":         r.status_code == 200,
        }
    except requests.exceptions.RequestException as e:
        latency_ms = (time.monotonic() - start) * 1000
        return {
            "label":      label,
            "url":        url,
            "status":     None,
            "latency_ms": latency_ms,
            "body":       {"error": str(e)},
            "ok":         False,
        }


# ── Result printer ────────────────────────────────────────────────────────────

def print_result(result: dict, expected_region: str):
    """Print a formatted result row and assert the region."""
    label      = result["label"]
    status     = result["status"]
    latency    = result["latency_ms"]
    body       = result["body"]
    ok         = result["ok"]

    actual_region = body.get("region", "")
    region_match  = actual_region == expected_region

    status_icon = PASS if ok else FAIL
    region_icon = PASS if region_match else FAIL

    print(f"\n  {CYAN}{BOLD}{label}{RESET}")
    print(f"    HTTP Status    : {status}  {status_icon}")
    print(f"    Latency        : {latency:.1f} ms")
    print(f"    Expected region: {expected_region}")
    print(f"    Actual region  : {actual_region or '(missing)'}  {region_icon}")
    print(f"    Body           : {json.dumps(body, indent=6)}")

    return ok and region_match


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Unleash live deployment test")
    parser.add_argument("--user-pool-id", default=os.getenv("COGNITO_USER_POOL_ID"))
    parser.add_argument("--client-id",    default=os.getenv("COGNITO_CLIENT_ID"))
    parser.add_argument("--username",     default=os.getenv("COGNITO_USERNAME"))
    parser.add_argument("--password",     default=os.getenv("COGNITO_PASSWORD"))
    parser.add_argument("--api-us",       default=os.getenv("API_ENDPOINT_US"))
    parser.add_argument("--api-eu",       default=os.getenv("API_ENDPOINT_EU"))
    args = parser.parse_args()

    missing = [k for k, v in vars(args).items() if not v]
    if missing:
        print(f"{RED}Missing required arguments/env vars: {missing}{RESET}")
        parser.print_help()
        sys.exit(1)

    api_us = args.api_us.rstrip("/")
    api_eu = args.api_eu.rstrip("/")

    # ── Auth ──────────────────────────────────────────────────────────────────
    token = get_jwt(args.user_pool_id, args.client_id, args.username, args.password)

    all_passed = True

    # ── Step 2: Concurrent /greet ─────────────────────────────────────────────
    print(f"\n{BOLD}── Step 2: Concurrent /greet calls ─────────────────────────────{RESET}")
    greet_tasks = [
        ("GET /greet  [us-east-1]", f"{api_us}/greet", token, "GET", "us-east-1"),
        ("GET /greet  [eu-west-1]", f"{api_eu}/greet", token, "GET", "eu-west-1"),
    ]
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        futures = {
            executor.submit(call_endpoint, label, url, tok, method): expected
            for label, url, tok, method, expected in greet_tasks
        }
        for future, expected in futures.items():
            result = future.result()
            passed = print_result(result, expected)
            all_passed = all_passed and passed

    # ── Step 3: Concurrent /dispatch ─────────────────────────────────────────
    print(f"\n{BOLD}── Step 3: Concurrent /dispatch calls ──────────────────────────{RESET}")
    dispatch_tasks = [
        ("POST /dispatch [us-east-1]", f"{api_us}/dispatch", token, "POST", "us-east-1"),
        ("POST /dispatch [eu-west-1]", f"{api_eu}/dispatch", token, "POST", "eu-west-1"),
    ]
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        futures = {
            executor.submit(call_endpoint, label, url, tok, method): expected
            for label, url, tok, method, expected in dispatch_tasks
        }
        for future, expected in futures.items():
            result = future.result()
            passed = print_result(result, expected)
            all_passed = all_passed and passed

    # ── Summary ───────────────────────────────────────────────────────────────
    print(f"\n{BOLD}── Summary ─────────────────────────────────────────────────────{RESET}")
    if all_passed:
        print(f"  {PASS}  All assertions passed.")
    else:
        print(f"  {FAIL}  One or more assertions failed.")
        sys.exit(1)


if __name__ == "__main__":
    main()
