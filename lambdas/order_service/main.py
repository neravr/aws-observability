import json
import os
import random
import time
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.resources import Resource
from aws_xray_sdk.core import xray_recorder, patch_all

patch_all()

resource = Resource.create({"service.name": "order-service"})
provider = TracerProvider(resource=resource)
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# Error rate — 30% of requests fail to generate observable errors
ERROR_RATE = float(os.environ.get("ERROR_RATE", "0.3"))

def lambda_handler(event, context):
    """
    Order service — processes orders with intentional failures
    to generate observable error patterns in CloudWatch and X-Ray.
    """
    with tracer.start_as_current_span("order-service.process_order") as span:
        order_id   = event.get("order_id", "unknown")
        customer_id = event.get("customer_id", "unknown")
        items      = event.get("items", [])

        span.set_attribute("order.id",       order_id)
        span.set_attribute("customer.id",    customer_id)
        span.set_attribute("order.item_count", len(items))

        # Simulate processing time
        processing_time = random.uniform(0.05, 0.3)
        time.sleep(processing_time)
        span.set_attribute("processing.time_ms", processing_time * 1000)

        # Intentional failures to generate error metrics
        if random.random() < ERROR_RATE:
            error_types = [
                "InventoryServiceUnavailable",
                "PaymentGatewayTimeout",
                "DatabaseConnectionError",
                "InvalidOrderState"
            ]
            error = random.choice(error_types)

            span.set_attribute("error", True)
            span.set_attribute("error.type", error)
            span.record_exception(Exception(error))

            print(f"ERROR: Order {order_id} failed with {error}")

            raise Exception(f"Order processing failed: {error}")

        # Successful order
        span.set_attribute("order.status", "fulfilled")
        print(f"Order {order_id} fulfilled successfully")

        return {
            "statusCode": 200,
            "order_id":   order_id,
            "status":     "fulfilled",
            "items":      items,
            "processing_time_ms": processing_time * 1000
        }