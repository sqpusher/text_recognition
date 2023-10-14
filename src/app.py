import json

from recognizer import read_image


def lambda_handler(event, context):
    if body := event.get('body'):
        data = json.loads(body)
        if isinstance(data, str):
            res = read_image(data)

            return {
                "statusCode": 200,
                "headers": {
                    "Content-Type": "application/json"
                },
                "body": json.dumps({"text": res})
            }

    return {
        "statusCode": 400,
        "body": json.dumps({"error": "No or wrong body provided"})
    }
