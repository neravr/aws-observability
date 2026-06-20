import json
import boto3
import os
import random
import time
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from aws_xray_sdk.core import xray_recorder, patch_all

# Patch all supported libraries for X-Ray
patch_all()

# Initialize tracer
resource = Resource.create({"service.name": "app-service"})
provider = TracerProvider(resource=resource)
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

lambda_client = boto3.client("lambda", region_name=os.environ.get("AWS_REGION", "us-east-1"))

def lambda_handler(event, context):
    """
    Main app service — receives order requests and calls order-service.
    Instrumented with OpenTelemetry for distributed tracing.
    """
    with tracer.start_as_current_span("app-service.process_request") as span:
        order_id = event.get("order_id", f"ORD-{random.randint(1000, 9999)}")
        customer_id = event.get("customer_id", f"CUST-{random.randint(100, 999)}")

        span.set_attribute("order.id", order_id)
        span.set_attribute("customer.id", customer_id)

        print(f"Processing order {order_id} for customer {customer_id}")

        # Call order-service
        try:
            with tracer.start_as_current_span("app-service.call_order_service") as child_span:
                order_env = os.environ.get("ENV", "dev")
                response = lambda_client.invoke(
                    FunctionName=f"order-service-{order_env}",
                    InvocationType="RequestResponse",
                    Payload=json.dumps({
                        "order_id":    order_id,
                        "customer_id": customer_id,
                        "items":       event.get("items", ["item-1", "item-2"])
                    })
                )

                payload = json.loads(response["Payload"].read())
                child_span.set_attribute("order_service.status_code", response["StatusCode"])

                if response["StatusCode"] == 200:
                    span.set_attribute("request.success", True)
                    return {
                        "statusCode": 200,
                        "body": json.dumps({
                            "order_id":   order_id,
                            "status":     "processed",
                            "details":    payload
                        })
                    }
                else:
                    span.set_attribute("request.success", False)
                    raise Exception(f"Order service returned {response['StatusCode']}")

        except Exception as e:
            span.set_attribute("error", True)
            span.set_attribute("error.message", str(e))
            print(f"Error processing order {order_id}: {e}")
            return {
                "statusCode": 500,
                "body": json.dumps({
                    "error":    str(e),
                    "order_id": order_id
                })
            }