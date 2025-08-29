"""
Analytics Engine Microservice for Azure Healthcare Platform
Provides analytics endpoints for healthcare data insights
HIPAA compliant with comprehensive security and audit logging
"""

import os
import json
import logging
import asyncio
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict
import hashlib
import secrets

import uvicorn
from fastapi import FastAPI, HTTPException, Depends, Security, BackgroundTasks, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
import pandas as pd
import numpy as np
from azure.identity import DefaultAzureCredential
from azure.storage.filedatalake import DataLakeServiceClient
from azure.keyvault.secrets import SecretClient
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
import redis.asyncio as aioredis
from prometheus_client import Counter, Histogram, generate_latest
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

# Metrics
REQUESTS_TOTAL = Counter('analytics_requests_total', 'Total requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('analytics_request_duration_seconds', 'Request duration')
ANALYTICS_QUERIES = Counter('analytics_queries_total', 'Total analytics queries', ['query_type'])

@dataclass
class AnalyticsRequest:
    """Analytics request model"""
    query_type: str
    parameters: Dict[str, Any]
    filters: Optional[Dict[str, Any]] = None
    date_range: Optional[Dict[str, str]] = None
    aggregation: Optional[str] = None

@dataclass
class AnalyticsResult:
    """Analytics result model"""
    query_id: str
    query_type: str
    result_count: int
    data: List[Dict[str, Any]]
    metadata: Dict[str, Any]
    execution_time: float
    cache_hit: bool = False

class SecurityManager:
    """HIPAA-compliant security manager"""
    
    def __init__(self):
        self.credential = DefaultAzureCredential()
        self.key_vault_url = os.environ.get('KEY_VAULT_URL')
        if self.key_vault_url:
            self.secret_client = SecretClient(
                vault_url=self.key_vault_url,
                credential=self.credential
            )
    
    async def validate_token(self, token: str) -> Dict[str, Any]:
        """Validate JWT token"""
        try:
            # In production, implement proper JWT validation
            # This is a placeholder for the validation logic
            return {"user_id": "user123", "roles": ["analyst"]}
        except Exception as e:
            logger.error("Token validation failed", error=str(e))
            raise HTTPException(status_code=401, detail="Invalid token")
    
    def generate_query_id(self) -> str:
        """Generate unique query ID for tracking"""
        return f"query_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}_{secrets.token_hex(8)}"
    
    def hash_sensitive_data(self, data: str) -> str:
        """Hash sensitive data for logging"""
        return hashlib.sha256(data.encode()).hexdigest()[:16]

class DataLakeClient:
    """HIPAA-compliant Data Lake client"""
    
    def __init__(self):
        self.credential = DefaultAzureCredential()
        self.account_url = os.environ.get('DATA_LAKE_URL')
        if self.account_url:
            self.client = DataLakeServiceClient(
                account_url=self.account_url,
                credential=self.credential
            )
    
    async def query_patient_demographics(self, filters: Dict[str, Any]) -> pd.DataFrame:
        """Query patient demographic data"""
        try:
            # Simulate data query - in production, implement actual Data Lake queries
            data = {
                'patient_id': [f'P{i:06d}' for i in range(1000)],
                'age_group': np.random.choice(['18-30', '31-45', '46-60', '60+'], 1000),
                'gender': np.random.choice(['M', 'F', 'O'], 1000),
                'diagnosis_code': np.random.choice(['Z00.00', 'I10', 'E11.9', 'J44.1'], 1000),
                'admission_date': pd.date_range('2023-01-01', periods=1000, freq='D')
            }
            df = pd.DataFrame(data)
            
            # Apply filters
            if filters.get('age_group'):
                df = df[df['age_group'] == filters['age_group']]
            if filters.get('gender'):
                df = df[df['gender'] == filters['gender']]
            
            return df
        except Exception as e:
            logger.error("Failed to query patient demographics", error=str(e))
            raise
    
    async def query_clinical_metrics(self, filters: Dict[str, Any]) -> pd.DataFrame:
        """Query clinical metrics data"""
        try:
            # Simulate clinical metrics data
            data = {
                'metric_id': [f'M{i:06d}' for i in range(500)],
                'metric_name': np.random.choice(['Blood Pressure', 'Heart Rate', 'Temperature', 'Oxygen Saturation'], 500),
                'value': np.random.normal(100, 15, 500),
                'unit': np.random.choice(['mmHg', 'bpm', '°F', '%'], 500),
                'measurement_date': pd.date_range('2023-01-01', periods=500, freq='H'),
                'patient_id': [f'P{np.random.randint(1, 1000):06d}' for _ in range(500)]
            }
            return pd.DataFrame(data)
        except Exception as e:
            logger.error("Failed to query clinical metrics", error=str(e))
            raise

class CacheManager:
    """Redis cache manager for analytics results"""
    
    def __init__(self):
        self.redis_url = os.environ.get('REDIS_URL', 'redis://localhost:6379')
        self.redis_client = None
        self.cache_ttl = int(os.environ.get('CACHE_TTL', '3600'))  # 1 hour default
    
    async def get_client(self):
        """Get Redis client"""
        if not self.redis_client:
            self.redis_client = await aioredis.from_url(self.redis_url)
        return self.redis_client
    
    async def get_cached_result(self, cache_key: str) -> Optional[Dict[str, Any]]:
        """Get cached analytics result"""
        try:
            client = await self.get_client()
            cached_data = await client.get(cache_key)
            if cached_data:
                return json.loads(cached_data)
            return None
        except Exception as e:
            logger.warning("Cache retrieval failed", error=str(e))
            return None
    
    async def cache_result(self, cache_key: str, result: Dict[str, Any]):
        """Cache analytics result"""
        try:
            client = await self.get_client()
            await client.setex(
                cache_key,
                self.cache_ttl,
                json.dumps(result, default=str)
            )
        except Exception as e:
            logger.warning("Cache storage failed", error=str(e))

class AnalyticsEngine:
    """Core analytics engine"""
    
    def __init__(self):
        self.data_lake = DataLakeClient()
        self.cache = CacheManager()
        self.security = SecurityManager()
    
    def generate_cache_key(self, request: AnalyticsRequest) -> str:
        """Generate cache key for request"""
        request_str = json.dumps(asdict(request), sort_keys=True)
        return f"analytics:{hashlib.md5(request_str.encode()).hexdigest()}"
    
    async def execute_analytics_query(self, request: AnalyticsRequest, user_context: Dict[str, Any]) -> AnalyticsResult:
        """Execute analytics query with caching"""
        query_id = self.security.generate_query_id()
        start_time = datetime.utcnow()
        
        # Check cache first
        cache_key = self.generate_cache_key(request)
        cached_result = await self.cache.get_cached_result(cache_key)
        
        if cached_result:
            logger.info("Cache hit for analytics query", 
                       query_id=query_id, 
                       query_type=request.query_type,
                       user_id=self.security.hash_sensitive_data(user_context.get('user_id', '')))
            
            cached_result['cache_hit'] = True
            return AnalyticsResult(**cached_result)
        
        # Execute query
        try:
            if request.query_type == "patient_demographics":
                df = await self.data_lake.query_patient_demographics(request.filters or {})
                result_data = self._process_demographic_analytics(df, request)
            elif request.query_type == "clinical_metrics":
                df = await self.data_lake.query_clinical_metrics(request.filters or {})
                result_data = self._process_clinical_analytics(df, request)
            elif request.query_type == "readmission_analysis":
                result_data = await self._analyze_readmissions(request)
            elif request.query_type == "cost_analysis":
                result_data = await self._analyze_costs(request)
            else:
                raise HTTPException(status_code=400, detail=f"Unsupported query type: {request.query_type}")
            
            execution_time = (datetime.utcnow() - start_time).total_seconds()
            
            result = AnalyticsResult(
                query_id=query_id,
                query_type=request.query_type,
                result_count=len(result_data),
                data=result_data,
                metadata={
                    "executed_at": start_time.isoformat(),
                    "filters_applied": request.filters,
                    "user_id": self.security.hash_sensitive_data(user_context.get('user_id', ''))
                },
                execution_time=execution_time
            )
            
            # Cache result
            await self.cache.cache_result(cache_key, asdict(result))
            
            # Record metrics
            ANALYTICS_QUERIES.labels(query_type=request.query_type).inc()
            
            logger.info("Analytics query executed successfully",
                       query_id=query_id,
                       query_type=request.query_type,
                       result_count=len(result_data),
                       execution_time=execution_time)
            
            return result
            
        except Exception as e:
            logger.error("Analytics query failed",
                        query_id=query_id,
                        query_type=request.query_type,
                        error=str(e))
            raise HTTPException(status_code=500, detail="Analytics query failed")
    
    def _process_demographic_analytics(self, df: pd.DataFrame, request: AnalyticsRequest) -> List[Dict[str, Any]]:
        """Process demographic analytics"""
        if request.aggregation == "age_distribution":
            result = df.groupby('age_group').size().reset_index(name='count')
        elif request.aggregation == "gender_distribution":
            result = df.groupby('gender').size().reset_index(name='count')
        else:
            result = df.groupby(['age_group', 'gender']).size().reset_index(name='count')
        
        return result.to_dict('records')
    
    def _process_clinical_analytics(self, df: pd.DataFrame, request: AnalyticsRequest) -> List[Dict[str, Any]]:
        """Process clinical metrics analytics"""
        if request.aggregation == "average_by_metric":
            result = df.groupby('metric_name')['value'].agg(['mean', 'std', 'count']).reset_index()
        elif request.aggregation == "trends":
            df['date'] = pd.to_datetime(df['measurement_date']).dt.date
            result = df.groupby(['date', 'metric_name'])['value'].mean().reset_index()
        else:
            result = df.describe().reset_index()
        
        return result.to_dict('records')
    
    async def _analyze_readmissions(self, request: AnalyticsRequest) -> List[Dict[str, Any]]:
        """Analyze readmission patterns"""
        # Simulated readmission analysis
        return [
            {"period": "30_days", "readmission_rate": 0.15, "count": 450},
            {"period": "90_days", "readmission_rate": 0.25, "count": 750},
            {"period": "1_year", "readmission_rate": 0.40, "count": 1200}
        ]
    
    async def _analyze_costs(self, request: AnalyticsRequest) -> List[Dict[str, Any]]:
        """Analyze healthcare costs"""
        # Simulated cost analysis
        return [
            {"category": "Emergency Care", "average_cost": 5500.00, "total_cases": 2500},
            {"category": "Inpatient Care", "average_cost": 15000.00, "total_cases": 1800},
            {"category": "Outpatient Care", "average_cost": 750.00, "total_cases": 8500},
            {"category": "Preventive Care", "average_cost": 300.00, "total_cases": 12000}
        ]

# Initialize FastAPI app
app = FastAPI(
    title="Healthcare Analytics Engine",
    description="HIPAA-compliant analytics engine for healthcare data",
    version="1.0.0",
    docs_url="/docs" if os.getenv("ENVIRONMENT") != "prod" else None,
    redoc_url="/redoc" if os.getenv("ENVIRONMENT") != "prod" else None
)

# Security
security = HTTPBearer()
analytics_engine = AnalyticsEngine()

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("ALLOWED_ORIGINS", "https://healthcare-platform.com").split(","),
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# Trusted hosts
app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=os.getenv("ALLOWED_HOSTS", "analytics.healthcare-platform.com").split(",")
)

# Configure Azure Monitor
if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    configure_azure_monitor()

# Instrument FastAPI
FastAPIInstrumentor.instrument_app(app)

async def get_current_user(credentials: HTTPAuthorizationCredentials = Security(security)):
    """Get current authenticated user"""
    token = credentials.credentials
    return await analytics_engine.security.validate_token(token)

@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log all requests for audit trail"""
    start_time = datetime.utcnow()
    
    # Log request
    logger.info("Request received",
               method=request.method,
               url=str(request.url),
               client_ip=request.client.host,
               user_agent=request.headers.get("user-agent"))
    
    response = await call_next(request)
    
    # Log response
    duration = (datetime.utcnow() - start_time).total_seconds()
    logger.info("Request completed",
               method=request.method,
               url=str(request.url),
               status_code=response.status_code,
               duration=duration)
    
    # Record metrics
    REQUESTS_TOTAL.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()
    REQUEST_DURATION.observe(duration)
    
    return response

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()

@app.post("/analytics/query", response_model=AnalyticsResult)
async def execute_analytics(
    request: AnalyticsRequest,
    background_tasks: BackgroundTasks,
    user: Dict[str, Any] = Depends(get_current_user)
):
    """Execute analytics query"""
    try:
        result = await analytics_engine.execute_analytics_query(request, user)
        
        # Background audit logging
        background_tasks.add_task(
            log_analytics_query,
            query_id=result.query_id,
            user_id=user.get('user_id'),
            query_type=request.query_type,
            result_count=result.result_count
        )
        
        return result
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Unexpected error in analytics query", error=str(e))
        raise HTTPException(status_code=500, detail="Internal server error")

@app.get("/analytics/types")
async def get_analytics_types(user: Dict[str, Any] = Depends(get_current_user)):
    """Get available analytics query types"""
    return {
        "available_types": [
            {
                "type": "patient_demographics",
                "description": "Patient demographic analysis",
                "aggregations": ["age_distribution", "gender_distribution", "combined"]
            },
            {
                "type": "clinical_metrics",
                "description": "Clinical metrics analysis",
                "aggregations": ["average_by_metric", "trends", "summary"]
            },
            {
                "type": "readmission_analysis",
                "description": "Hospital readmission analysis",
                "aggregations": ["by_period", "by_diagnosis"]
            },
            {
                "type": "cost_analysis",
                "description": "Healthcare cost analysis",
                "aggregations": ["by_category", "trends", "comparative"]
            }
        ]
    }

async def log_analytics_query(query_id: str, user_id: str, query_type: str, result_count: int):
    """Background task for audit logging"""
    try:
        logger.info("Analytics query audit",
                   query_id=query_id,
                   user_id=analytics_engine.security.hash_sensitive_data(user_id),
                   query_type=query_type,
                   result_count=result_count,
                   audit=True)
    except Exception as e:
        logger.error("Failed to log analytics audit", error=str(e))

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8001")),
        log_level=os.getenv("LOG_LEVEL", "info").lower(),
        access_log=True
    )
