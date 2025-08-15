import pika
import time
import logging
import os
from prometheus_client import Gauge, Counter, start_http_server
from datetime import datetime
import threading
import ssl

# Prometheus metrics
availability_gauge = Gauge('rabbitmq_functional_availability', 'RabbitMQ functional availability (1=up, 0=down)')
probe_duration_gauge = Gauge('rabbitmq_probe_duration_seconds', 'Time taken for RabbitMQ probe')
probe_total_counter = Counter('rabbitmq_probe_total', 'Total number of probes')
probe_failures_counter = Counter('rabbitmq_probe_failures_total', 'Total number of failed probes')

# Configuration
RABBITMQ_HOST = os.getenv('RABBITMQ_HOST', 'rabbitmq')
RABBITMQ_PORT = int(os.getenv('RABBITMQ_PORT', '5671'))
RABBITMQ_USER = os.getenv('RABBITMQ_USER', 'user')
RABBITMQ_PASSWORD = os.getenv('RABBITMQ_PASSWORD', 'password')
RABBITMQ_USE_TLS = os.getenv('RABBITMQ_USE_TLS', 'true').lower() == 'true'
PROBE_INTERVAL = int(os.getenv('PROBE_INTERVAL', '30'))
METRICS_PORT = int(os.getenv('METRICS_PORT', '8080'))
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')

# Setup logging
logging.basicConfig(level=getattr(logging, LOG_LEVEL.upper()),
                   format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)
logging.getLogger('pika').setLevel(logging.ERROR)

def probe_rabbitmq():
    """Test RabbitMQ by publishing and consuming a message"""
    start_time = time.time()
    probe_total_counter.inc()
    connection = None

    try:
        # Setup connection
        credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
        ssl_options = None

        if RABBITMQ_USE_TLS:
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
            ssl_options = pika.SSLOptions(ssl_context)

        parameters = pika.ConnectionParameters(
            host=RABBITMQ_HOST,
            port=RABBITMQ_PORT,
            virtual_host='/',
            credentials=credentials,
            ssl_options=ssl_options,
            socket_timeout=10,
            connection_attempts=3
        )

        # Connect and test
        connection = pika.BlockingConnection(parameters)
        channel = connection.channel()
        logger.info("Connected to RabbitMQ")

        # Create test queue
        queue_name = f'health_check_{int(time.time())}'
        channel.queue_declare(queue=queue_name, durable=False, auto_delete=True, exclusive=True)

        # Publish and consume test message
        test_message = f'test_{datetime.now().isoformat()}'
        channel.basic_publish(exchange='', routing_key=queue_name, body=test_message)

        method, properties, body = channel.basic_get(queue=queue_name, auto_ack=True)
        if not body or body.decode('utf-8') != test_message:
            raise Exception("Message test failed")

        # Cleanup
        channel.queue_delete(queue=queue_name)

        # Success
        duration = time.time() - start_time
        probe_duration_gauge.set(duration)
        availability_gauge.set(1)
        logger.info("Successfully probed RabbitMQ")
        return True

    except Exception as e:
        duration = time.time() - start_time
        probe_duration_gauge.set(duration)
        availability_gauge.set(0)
        probe_failures_counter.inc()
        logger.error(f"RabbitMQ probe failed: {str(e)}")
        return False

    finally:
        if connection and not connection.is_closed:
            try:
                connection.close()
                logger.info("Disconnected from RabbitMQ")
            except Exception as e:
                logger.error(f"Error closing connection: {e}")

def probe_loop():
    """Main probe loop"""
    logger.info(f"Starting RabbitMQ prober - {RABBITMQ_HOST}:{RABBITMQ_PORT}")

    while True:
        try:
            probe_rabbitmq()
        except Exception as e:
            logger.error(f"Unexpected error: {str(e)}")
            availability_gauge.set(0)
            probe_failures_counter.inc()

        time.sleep(PROBE_INTERVAL)

if __name__ == "__main__":
    # Start metrics server
    start_http_server(METRICS_PORT)
    logger.info(f"Metrics server started on port {METRICS_PORT}")

    # Start probing
    probe_thread = threading.Thread(target=probe_loop, daemon=True)
    probe_thread.start()

    try:
        probe_thread.join()
    except KeyboardInterrupt:
        logger.info("Shutting down...")
