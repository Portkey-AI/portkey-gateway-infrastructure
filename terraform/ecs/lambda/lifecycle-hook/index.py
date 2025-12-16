import os
import json

def hook_succeeded():
    print("Sending hookStatus SUCCEEDED back to ECS")
    return {"hookStatus": "SUCCEEDED"}


def hook_failed():
    print("Sending hookStatus FAILED back to ECS")
    return {"hookStatus": "FAILED"}


def hook_in_progress(revision_id):
    print("Sending hookStatus IN_PROGRESS back to ECS")
    return {
        "hookStatus": "IN_PROGRESS",
        "callBackDelay": 30,
        "hookDetails": {}
    }

def handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    # Custom logic for hook 

    return hook_succeeded()
    
    