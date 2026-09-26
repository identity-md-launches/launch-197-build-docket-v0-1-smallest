#!/usr/bin/env python3
"""Record local transaction gas; requires a fresh DOCKET on an unlocked Anvil node."""
import argparse
import json
from pathlib import Path
import subprocess
import time
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("address")
parser.add_argument("--rpc-url", default="http://127.0.0.1:8545")
args = parser.parse_args()


def rpc(method, params):
    data = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    request = urllib.request.Request(args.rpc_url, data, {"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        result = json.load(response)
    if "error" in result:
        raise RuntimeError(result["error"])
    return result["result"]


def calldata(signature, *values):
    return subprocess.check_output(["cast", "calldata", signature, *map(str, values)], text=True).strip()


def transact(label, signature, *values):
    data = calldata(signature, *values)
    tx_hash = rpc("eth_sendTransaction", [{
        "from": sender, "to": args.address, "data": data, "gas": hex(500_000)
    }])
    for _ in range(100):
        receipt = rpc("eth_getTransactionReceipt", [tx_hash])
        if receipt is not None:
            break
        time.sleep(0.1)
    else:
        raise RuntimeError("Timed out waiting for receipt")
    if receipt["status"] != "0x1" or len(receipt["logs"]) != 1:
        raise RuntimeError(f"Unexpected transaction receipt: {receipt}")
    # Cancun, ordinary non-creation transactions, no access list or refunds in DOCKET.
    intrinsic = 21_000 + sum(4 if b == 0 else 16 for b in bytes.fromhex(data[2:]))
    execution = int(receipt["gasUsed"], 16) - intrinsic
    if (signature == "upvote(uint256,uint256)" or
            (signature == "comment(uint256,string)" and len(values[1].encode()) == 500)):
        if execution >= 50_000:
            raise RuntimeError(f"Execution gas budget exceeded: {label}: {execution}")
    rows.append({
        "case": label, "address": args.address, "txHash": tx_hash,
        "block": int(receipt["blockNumber"], 16), "gasUsed": int(receipt["gasUsed"], 16),
        "intrinsicGas": intrinsic, "executionGas": execution, "receipt": receipt
    })


if int(rpc("eth_chainId", []), 16) != 31337:
    raise RuntimeError("Local Anvil chain 31337 only")
compiled = json.loads(Path("out/Docket.sol/Docket.json").read_text())
if rpc("eth_getCode", [args.address, "latest"]) != compiled["deployedBytecode"]["object"]:
    raise RuntimeError("Runtime mismatch")
if int(rpc("eth_call", [{"to": args.address, "data": calldata("ideaCount()")}, "latest"]), 16) != 0:
    raise RuntimeError("Use a fresh deployment")
sender = rpc("eth_accounts", [])[0]
rows = []
for idea_id, (label, title_length, body_length, comment_length) in enumerate([
    ("small", 1, 1, 1), ("typical", 40, 500, 500), ("maximum", 120, 4000, 2000)
], 1):
    state = "first idea" if idea_id == 1 else "subsequent idea"
    transact(f"createIdea {label} ({state})", "createIdea(string,string)", "x" * title_length, "x" * body_length)
    for state in ("first", "subsequent"):
        transact(f"comment {label} ({state} on idea)", "comment(uint256,string)", idea_id, "x" * comment_length)
    transact(f"upvote {label} idea (first)", "upvote(uint256,uint256)", idea_id, 0)
    transact(f"upvote {label} comment (first)", "upvote(uint256,uint256)", idea_id, 1)
print(json.dumps({"chainId": 31337, "hardforkAssumption": "cancun (start Anvil with --hardfork cancun)", "transactions": rows}, indent=2))
