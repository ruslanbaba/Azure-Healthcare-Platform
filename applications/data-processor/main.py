"""
Azure Healthcare Data Processor
HIPAA-compliant data processing service for healthcare analytics platform
"""

import os
import asyncio
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime, timezone
import json
import hashlib
from dataclasses import dataclass, asdict
from azure.storage.blob.aio import BlobServiceClient
from azure.identity.aio import DefaultAzureCredential
from azure.keyvault.secrets.aio import SecretClient
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry import trace
from cryptography.fernet import Fernet
import pandas as pd
import numpy as np
from pydantic import BaseModel, Field, validator
import structlog

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# Configure Azure Monitor for telemetry
configure_azure_monitor(
    connection_string=os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")
)
tracer = trace.get_tracer(__name__)

@dataclass
class PatientRecord:
    """HIPAA-compliant patient record structure"""
    patient_id: str
    encrypted_data: str
    data_hash: str
    timestamp: datetime
    source_system: str
    data_classification: str = "PHI"
    
    def __post_init__(self):
        if not self.data_hash:
            self.data_hash = self._generate_hash()
    
    def _generate_hash(self) -> str:
        """Generate SHA-256 hash for data integrity"""
        return hashlib.sha256(self.encrypted_data.encode()).hexdigest()

class DataProcessingConfig(BaseModel):
    """Configuration for data processing pipeline"""
    batch_size: int = Field(default=1000, ge=1, le=10000)
    encryption_key_name: str = Field(default="data-encryption-key")
    source_container: str = Field(default="raw")
    target_container: str = Field(default="processed")
    enable_phi_detection: bool = Field(default=True)
    data_retention_days: int = Field(default=2555)  # 7 years HIPAA requirement
    
    @validator('batch_size')
    def validate_batch_size(cls, v):
        if v > 10000:
            raise ValueError('Batch size cannot exceed 10000 for performance')
        return v

class HealthcareDataProcessor:
    """
    HIPAA-compliant healthcare data processor
    Handles secure processing of 150M+ patient records
    """
    
    def __init__(self, config: DataProcessingConfig):
        self.config = config
        self.credential = DefaultAzureCredential()
        self.encryption_key: Optional[bytes] = None
        self.blob_client: Optional[BlobServiceClient] = None
        self.secret_client: Optional[SecretClient] = None
        
    async def initialize(self):
        """Initialize Azure clients and encryption keys"""
        with tracer.start_as_current_span("initialize_processor"):
            try:
                # Initialize blob storage client
                storage_account_name = os.environ.get("STORAGE_ACCOUNT_NAME")
                if not storage_account_name:
                    raise ValueError("STORAGE_ACCOUNT_NAME environment variable is required")
                
                account_url = f"https://{storage_account_name}.blob.core.windows.net"
                self.blob_client = BlobServiceClient(
                    account_url=account_url,
                    credential=self.credential
                )
                
                # Initialize Key Vault client
                key_vault_url = os.environ.get("KEY_VAULT_URL")
                if not key_vault_url:
                    raise ValueError("KEY_VAULT_URL environment variable is required")
                
                self.secret_client = SecretClient(
                    vault_url=key_vault_url,
                    credential=self.credential
                )
                
                # Get encryption key from Key Vault
                encryption_key_secret = await self.secret_client.get_secret(
                    self.config.encryption_key_name
                )
                self.encryption_key = encryption_key_secret.value.encode()
                
                logger.info("Data processor initialized successfully",
                           storage_account=storage_account_name,
                           key_vault=key_vault_url)
                
            except Exception as e:
                logger.error("Failed to initialize data processor", error=str(e))
                raise

    async def process_healthcare_data(self, file_path: str) -> Dict[str, Any]:
        """
        Process healthcare data with HIPAA compliance
        
        Args:
            file_path: Path to the data file in storage
            
        Returns:
            Processing results with metrics
        """
        with tracer.start_as_current_span("process_healthcare_data") as span:
            span.set_attribute("file_path", file_path)
            
            start_time = datetime.now(timezone.utc)
            processed_records = 0
            failed_records = 0
            
            try:
                logger.info("Starting healthcare data processing",
                           file_path=file_path,
                           start_time=start_time.isoformat())
                
                # Download and decrypt data
                encrypted_data = await self._download_encrypted_data(file_path)
                decrypted_data = await self._decrypt_data(encrypted_data)
                
                # Parse healthcare records
                records = await self._parse_healthcare_records(decrypted_data)
                
                # Process records in batches
                batch_results = []
                for i in range(0, len(records), self.config.batch_size):
                    batch = records[i:i + self.config.batch_size]
                    batch_result = await self._process_batch(batch, i // self.config.batch_size)
                    batch_results.append(batch_result)
                    processed_records += batch_result.get("processed_count", 0)
                    failed_records += batch_result.get("failed_count", 0)
                
                # Generate processing report
                end_time = datetime.now(timezone.utc)
                processing_time = (end_time - start_time).total_seconds()
                
                result = {
                    "file_path": file_path,
                    "start_time": start_time.isoformat(),
                    "end_time": end_time.isoformat(),
                    "processing_time_seconds": processing_time,
                    "total_records": len(records),
                    "processed_records": processed_records,
                    "failed_records": failed_records,
                    "success_rate": processed_records / len(records) if records else 0,
                    "throughput_records_per_second": len(records) / processing_time if processing_time > 0 else 0,
                    "batch_results": batch_results
                }
                
                span.set_attribute("processed_records", processed_records)
                span.set_attribute("success_rate", result["success_rate"])
                
                logger.info("Healthcare data processing completed",
                           **{k: v for k, v in result.items() if k != "batch_results"})
                
                # Store processing audit log
                await self._store_audit_log(result)
                
                return result
                
            except Exception as e:
                logger.error("Healthcare data processing failed",
                           file_path=file_path,
                           error=str(e))
                span.record_exception(e)
                raise

    async def _download_encrypted_data(self, file_path: str) -> bytes:
        """Download encrypted data from blob storage"""
        with tracer.start_as_current_span("download_encrypted_data"):
            try:
                blob_client = self.blob_client.get_blob_client(
                    container=self.config.source_container,
                    blob=file_path
                )
                
                blob_data = await blob_client.download_blob()
                content = await blob_data.readall()
                
                logger.debug("Downloaded encrypted data",
                           file_path=file_path,
                           data_size=len(content))
                
                return content
                
            except Exception as e:
                logger.error("Failed to download encrypted data",
                           file_path=file_path,
                           error=str(e))
                raise

    async def _decrypt_data(self, encrypted_data: bytes) -> str:
        """Decrypt healthcare data using Fernet encryption"""
        with tracer.start_as_current_span("decrypt_data"):
            try:
                fernet = Fernet(self.encryption_key)
                decrypted_data = fernet.decrypt(encrypted_data)
                return decrypted_data.decode('utf-8')
                
            except Exception as e:
                logger.error("Failed to decrypt data", error=str(e))
                raise

    async def _parse_healthcare_records(self, data: str) -> List[Dict[str, Any]]:
        """Parse healthcare records from JSON data"""
        with tracer.start_as_current_span("parse_healthcare_records"):
            try:
                records = json.loads(data)
                if not isinstance(records, list):
                    records = [records]
                
                logger.debug("Parsed healthcare records", record_count=len(records))
                return records
                
            except Exception as e:
                logger.error("Failed to parse healthcare records", error=str(e))
                raise

    async def _process_batch(self, batch: List[Dict[str, Any]], batch_number: int) -> Dict[str, Any]:
        """Process a batch of healthcare records"""
        with tracer.start_as_current_span("process_batch") as span:
            span.set_attribute("batch_number", batch_number)
            span.set_attribute("batch_size", len(batch))
            
            processed_count = 0
            failed_count = 0
            processed_records = []
            
            try:
                for record in batch:
                    try:
                        # Validate record structure
                        validated_record = await self._validate_record(record)
                        
                        # Apply data transformations
                        transformed_record = await self._transform_record(validated_record)
                        
                        # Detect and mask PHI if enabled
                        if self.config.enable_phi_detection:
                            transformed_record = await self._mask_phi(transformed_record)
                        
                        # Encrypt processed data
                        encrypted_record = await self._encrypt_record(transformed_record)
                        
                        processed_records.append(encrypted_record)
                        processed_count += 1
                        
                    except Exception as e:
                        logger.warning("Failed to process record",
                                     batch_number=batch_number,
                                     record_id=record.get("id", "unknown"),
                                     error=str(e))
                        failed_count += 1
                
                # Store processed batch
                await self._store_processed_batch(processed_records, batch_number)
                
                batch_result = {
                    "batch_number": batch_number,
                    "processed_count": processed_count,
                    "failed_count": failed_count,
                    "success_rate": processed_count / len(batch) if batch else 0
                }
                
                logger.info("Batch processing completed", **batch_result)
                return batch_result
                
            except Exception as e:
                logger.error("Batch processing failed",
                           batch_number=batch_number,
                           error=str(e))
                raise

    async def _validate_record(self, record: Dict[str, Any]) -> Dict[str, Any]:
        """Validate healthcare record structure and required fields"""
        required_fields = ["patient_id", "timestamp", "data"]
        
        for field in required_fields:
            if field not in record:
                raise ValueError(f"Missing required field: {field}")
        
        # Validate patient ID format
        if not isinstance(record["patient_id"], str) or len(record["patient_id"]) < 5:
            raise ValueError("Invalid patient_id format")
        
        return record

    async def _transform_record(self, record: Dict[str, Any]) -> Dict[str, Any]:
        """Apply data transformations for analytics"""
        transformed = record.copy()
        
        # Standardize timestamp format
        if isinstance(transformed["timestamp"], str):
            transformed["timestamp"] = datetime.fromisoformat(
                transformed["timestamp"].replace("Z", "+00:00")
            ).isoformat()
        
        # Add processing metadata
        transformed["processing_timestamp"] = datetime.now(timezone.utc).isoformat()
        transformed["processor_version"] = "1.0.0"
        
        return transformed

    async def _mask_phi(self, record: Dict[str, Any]) -> Dict[str, Any]:
        """Mask PHI (Protected Health Information) in records"""
        masked_record = record.copy()
        
        # Example PHI masking (extend based on requirements)
        phi_fields = ["ssn", "phone", "email", "address"]
        
        for field in phi_fields:
            if field in masked_record:
                if field == "ssn":
                    masked_record[field] = "XXX-XX-" + masked_record[field][-4:]
                elif field == "phone":
                    masked_record[field] = "XXX-XXX-" + masked_record[field][-4:]
                else:
                    masked_record[field] = "***MASKED***"
        
        return masked_record

    async def _encrypt_record(self, record: Dict[str, Any]) -> PatientRecord:
        """Encrypt processed record for storage"""
        fernet = Fernet(self.encryption_key)
        
        record_json = json.dumps(record, sort_keys=True)
        encrypted_data = fernet.encrypt(record_json.encode()).decode()
        
        patient_record = PatientRecord(
            patient_id=record["patient_id"],
            encrypted_data=encrypted_data,
            data_hash="",  # Will be generated in __post_init__
            timestamp=datetime.now(timezone.utc),
            source_system="healthcare-data-processor"
        )
        
        return patient_record

    async def _store_processed_batch(self, records: List[PatientRecord], batch_number: int):
        """Store processed batch to target container"""
        with tracer.start_as_current_span("store_processed_batch"):
            try:
                batch_data = {
                    "batch_number": batch_number,
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "record_count": len(records),
                    "records": [asdict(record) for record in records]
                }
                
                batch_json = json.dumps(batch_data, indent=2)
                
                blob_name = f"batch_{batch_number:06d}_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.json"
                
                blob_client = self.blob_client.get_blob_client(
                    container=self.config.target_container,
                    blob=blob_name
                )
                
                await blob_client.upload_blob(batch_json, overwrite=True)
                
                logger.debug("Stored processed batch",
                           batch_number=batch_number,
                           blob_name=blob_name,
                           record_count=len(records))
                
            except Exception as e:
                logger.error("Failed to store processed batch",
                           batch_number=batch_number,
                           error=str(e))
                raise

    async def _store_audit_log(self, processing_result: Dict[str, Any]):
        """Store audit log for HIPAA compliance"""
        with tracer.start_as_current_span("store_audit_log"):
            try:
                audit_log = {
                    "event_type": "data_processing",
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "processing_result": processing_result,
                    "compliance_level": "HIPAA",
                    "processor_version": "1.0.0"
                }
                
                log_json = json.dumps(audit_log, indent=2)
                log_name = f"audit_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.json"
                
                blob_client = self.blob_client.get_blob_client(
                    container="logs",
                    blob=f"audit/{log_name}"
                )
                
                await blob_client.upload_blob(log_json, overwrite=True)
                
                logger.info("Stored audit log", log_name=log_name)
                
            except Exception as e:
                logger.error("Failed to store audit log", error=str(e))
                # Don't raise - audit log failure shouldn't stop processing

async def main():
    """Main entry point for the data processor"""
    try:
        config = DataProcessingConfig()
        processor = HealthcareDataProcessor(config)
        
        await processor.initialize()
        
        # Get file path from environment or command line
        file_path = os.environ.get("INPUT_FILE_PATH", "sample_data.json")
        
        result = await processor.process_healthcare_data(file_path)
        
        logger.info("Data processing completed successfully",
                   total_records=result["total_records"],
                   success_rate=result["success_rate"],
                   throughput=result["throughput_records_per_second"])
        
    except Exception as e:
        logger.error("Data processing failed", error=str(e))
        raise

if __name__ == "__main__":
    asyncio.run(main())
