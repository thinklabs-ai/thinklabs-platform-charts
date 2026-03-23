import json
import time
from kafka import KafkaConsumer, KafkaProducer

class MLOpsOrchestratorClient:
    def __init__(self, tenant, brokers, consumer_group):
        self.tenant = tenant
        self.brokers = brokers
        self.consumer_group = consumer_group
        self.request_topic = f"{tenant}.mlops.request"
        self.status_topic = f"{tenant}.mlops.status"
        self.response_topic = f"{tenant}.mlops.response"
        self.consumer = KafkaConsumer(
            self.request_topic,
            bootstrap_servers=self.brokers,
            group_id=self.consumer_group,
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            auto_offset_reset='earliest',
            enable_auto_commit=True
        )
        self.producer = KafkaProducer(
            bootstrap_servers=self.brokers,
            value_serializer=lambda m: json.dumps(m).encode('utf-8')
        )

    def wait_for_job(self, job_type, application, tenant=None, poll_interval=1):
        tenant = tenant or self.tenant
        for msg in self.consumer:
            req = msg.value
            if req.get('job_type') == job_type and req.get('application') == application and req.get('tenant') == tenant:
                run_id = req.get('run_id')
                self.update_status(run_id, job_type, application, tenant, req.get('workflow_id'), req.get('parent_run_id'), req.get('feeder_id'), 'RUNNING')
                return req
            # Commit skipped messages automatically
            time.sleep(poll_interval)

    def update_status(self, run_id, job_type, application, tenant, workflow_id, parent_run_id, feeder_id, status, details=None):
        event = {
            'run_id': run_id,
            'job_type': job_type,
            'application': application,
            'tenant': tenant,
            'workflow_id': workflow_id,
            'parent_run_id': parent_run_id,
            'feeder_id': feeder_id,
            'status': status,
            'details': details,
            'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        }
        self.producer.send(self.status_topic, event)
        self.producer.flush()

    def finalize_job(self, run_id, job_type, application, tenant, workflow_id, parent_run_id, feeder_id, output, summary, status):
        event = {
            'run_id': run_id,
            'job_type': job_type,
            'application': application,
            'tenant': tenant,
            'workflow_id': workflow_id,
            'parent_run_id': parent_run_id,
            'feeder_id': feeder_id,
            'output': output,
            'summary': summary,
            'status': status
        }
        self.producer.send(self.response_topic, event)
        self.producer.flush()
        self.update_status(run_id, job_type, application, tenant, workflow_id, parent_run_id, feeder_id, status)
