"""
API Gateway for Azure Healthcare Platform
Central entry point for all healthcare platform services
HIPAA compliant with comprehensive security, rate limiting, and audit logging
"""

import os
import json
import logging
import asyncio
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass
import hashlib
import secrets

import uvicorn
from fastapi import FastAPI, HTTPException, Depends, Security, BackgroundTasks, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
import httpx
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
import redis.asyncio as aioredis
from prometheus_client import Counter, Histogram, generate_latest
import structlog
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

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
REQUESTS_TOTAL = Counter('gateway_requests_total', 'Total requests', ['method', 'endpoint', 'status', 'service'])
REQUEST_DURATION = Histogram('gateway_request_duration_seconds', 'Request duration', ['service'])
RATE_LIMIT_HITS = Counter('gateway_rate_limit_hits_total', 'Rate limit hits', ['endpoint'])
CIRCUIT_BREAKER_OPENS = Counter('gateway_circuit_breaker_opens_total', 'Circuit breaker opens', ['service'])

@dataclass
class ServiceConfig:
    """Service configuration"""
    name: str
    url: str
    timeout: int = 30
    retry_count: int = 3
    circuit_breaker_threshold: int = 5

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
            # In production, implement proper JWT validation with Azure AD
            # This is a placeholder for the validation logic
            return {
                "user_id": "user123",
                "roles": ["analyst", "healthcare_provider"],
                "permissions": ["read:patients", "read:analytics", "write:data"]
            }
        except Exception as e:
            logger.error("Token validation failed", error=str(e))
            raise HTTPException(status_code=401, detail="Invalid token")
    
    def hash_sensitive_data(self, data: str) -> str:
        """Hash sensitive data for logging"""
        return hashlib.sha256(data.encode()).hexdigest()[:16]
    
    def generate_request_id(self) -> str:
        """Generate unique request ID for tracking"""
        return f"req_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}_{secrets.token_hex(8)}"

class CircuitBreaker:
    """Circuit breaker for service protection"""
    
    def __init__(self, threshold: int = 5, timeout: int = 60):
        self.threshold = threshold
        self.timeout = timeout
        self.failure_count = 0
        self.last_failure_time = None
        self.state = "CLOSED"  # CLOSED, OPEN, HALF_OPEN
    
    async def call(self, func, *args, **kwargs):
        """Execute function with circuit breaker protection"""
        if self.state == "OPEN":
            if datetime.utcnow().timestamp() - self.last_failure_time > self.timeout:
                self.state = "HALF_OPEN"
            else:
                raise HTTPException(status_code=503, detail="Service temporarily unavailable")
        
        try:
            result = await func(*args, **kwargs)
            if self.state == "HALF_OPEN":
                self.state = "CLOSED"
                self.failure_count = 0
            return result
        except Exception as e:
            self.failure_count += 1
            self.last_failure_time = datetime.utcnow().timestamp()
            
            if self.failure_count >= self.threshold:
                self.state = "OPEN"
                CIRCUIT_BREAKER_OPENS.labels(service=kwargs.get('service_name', 'unknown')).inc()
                logger.warning("Circuit breaker opened", 
                             service=kwargs.get('service_name', 'unknown'),
                             failure_count=self.failure_count)
            
            raise e

class ServiceRegistry:
    """Service registry for backend services"""
    
    def __init__(self):
        self.services = {
            "data-processor": ServiceConfig(
                name="data-processor",
                url=os.getenv("DATA_PROCESSOR_URL", "http://data-processor-service"),
                timeout=60,
                retry_count=2
            ),
            "analytics-engine": ServiceConfig(
                name="analytics-engine", 
                url=os.getenv("ANALYTICS_ENGINE_URL", "http://analytics-engine-service"),
                timeout=30,
                retry_count=3
            )
        }
        self.circuit_breakers = {
            name: CircuitBreaker(threshold=config.circuit_breaker_threshold)
            for name, config in self.services.items()
        }
    
    def get_service(self, name: str) -> Optional[ServiceConfig]:
        """Get service configuration"""
        return self.services.get(name)
    
    def get_circuit_breaker(self, name: str) -> Optional[CircuitBreaker]:
        """Get circuit breaker for service"""
        return self.circuit_breakers.get(name)

class APIGateway:
    """Main API Gateway class"""
    
    def __init__(self):
        self.security = SecurityManager()
        self.service_registry = ServiceRegistry()
        self.http_client = httpx.AsyncClient(
            timeout=httpx.Timeout(30.0),
            limits=httpx.Limits(max_keepalive_connections=20, max_connections=100)
        )
    
    async def proxy_request(
        self,
        service_name: str,
        path: str,
        method: str,
        headers: Dict[str, str],
        body: Optional[bytes] = None,
        query_params: Optional[Dict[str, str]] = None
    ) -> httpx.Response:
        """Proxy request to backend service with circuit breaker"""
        service_config = self.service_registry.get_service(service_name)
        if not service_config:
            raise HTTPException(status_code=404, detail=f"Service {service_name} not found")
        
        circuit_breaker = self.service_registry.get_circuit_breaker(service_name)
        
        async def make_request():
            url = f"{service_config.url}{path}"
            
            # Prepare headers
            proxy_headers = {k: v for k, v in headers.items() 
                           if k.lower() not in ['host', 'content-length']}
            proxy_headers['X-Forwarded-For'] = headers.get('X-Forwarded-For', '')
            proxy_headers['X-Request-ID'] = self.security.generate_request_id()
            
            # Make request with retries
            last_exception = None
            for attempt in range(service_config.retry_count):
                try:
                    response = await self.http_client.request(
                        method=method,
                        url=url,
                        headers=proxy_headers,
                        content=body,
                        params=query_params,
                        timeout=service_config.timeout
                    )
                    return response
                except httpx.RequestError as e:
                    last_exception = e
                    logger.warning(f"Request attempt {attempt + 1} failed",
                                 service=service_name,
                                 error=str(e))
                    if attempt < service_config.retry_count - 1:
                        await asyncio.sleep(2 ** attempt)  # Exponential backoff
            
            raise last_exception
        
        return await circuit_breaker.call(make_request, service_name=service_name)

# Initialize rate limiter
limiter = Limiter(key_func=get_remote_address)

# Initialize FastAPI app
app = FastAPI(
    title="Healthcare Platform API Gateway",
    description="HIPAA-compliant API Gateway for Healthcare Analytics Platform",
    version="1.0.0",
    docs_url="/docs" if os.getenv("ENVIRONMENT") != "prod" else None,
    redoc_url="/redoc" if os.getenv("ENVIRONMENT") != "prod" else None
)

# Add rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Security
security = HTTPBearer()
gateway = APIGateway()

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("ALLOWED_ORIGINS", "https://healthcare-platform.com").split(","),
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["*"],
)

# Trusted hosts
app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=os.getenv("ALLOWED_HOSTS", "api.healthcare-platform.com").split(",")
)

# Configure Azure Monitor
if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    configure_azure_monitor()

# Instrument FastAPI and HTTPX
FastAPIInstrumentor.instrument_app(app)
HTTPXClientInstrumentor().instrument()

async def get_current_user(credentials: HTTPAuthorizationCredentials = Security(security)):
    """Get current authenticated user"""
    token = credentials.credentials
    return await gateway.security.validate_token(token)

@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log all requests for audit trail"""
    start_time = datetime.utcnow()
    request_id = gateway.security.generate_request_id()
    
    # Add request ID to headers for downstream services
    request.state.request_id = request_id
    
    # Log request
    logger.info("Gateway request received",
               request_id=request_id,
               method=request.method,
               url=str(request.url),
               client_ip=request.client.host,
               user_agent=request.headers.get("user-agent"))
    
    response = await call_next(request)
    
    # Log response
    duration = (datetime.utcnow() - start_time).total_seconds()
    logger.info("Gateway request completed",
               request_id=request_id,
               method=request.method,
               url=str(request.url),
               status_code=response.status_code,
               duration=duration)
    
    # Record metrics
    service_name = request.url.path.split('/')[1] if len(request.url.path.split('/')) > 1 else 'unknown'
    REQUESTS_TOTAL.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code,
        service=service_name
    ).inc()
    REQUEST_DURATION.labels(service=service_name).observe(duration)
    
    # Add security headers
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["X-Request-ID"] = request_id
    
    return response

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()

@app.get("/services")
async def get_services(user: Dict[str, Any] = Depends(get_current_user)):
    """Get available services"""
    return {
        "services": [
            {
                "name": "data-processor",
                "description": "HIPAA-compliant data processing service",
                "endpoints": ["/data/process", "/data/validate", "/data/status"]
            },
            {
                "name": "analytics-engine", 
                "description": "Healthcare analytics and insights engine",
                "endpoints": ["/analytics/query", "/analytics/types"]
            }
        ]
    }

# Data Processing Service Proxy
@app.post("/data/process")
@limiter.limit("10/minute")
async def proxy_data_process(
    request: Request,
    background_tasks: BackgroundTasks,
    user: Dict[str, Any] = Depends(get_current_user)
):
    """Proxy to data processing service"""
    try:
        body = await request.body()
        response = await gateway.proxy_request(
            service_name="data-processor",
            path="/data/process",
            method="POST",
            headers=dict(request.headers),
            body=body
        )
        
        # Background audit logging
        background_tasks.add_task(
            log_service_call,
            service="data-processor",
            endpoint="/data/process",
            user_id=user.get('user_id'),
            status_code=response.status_code
        )
        
        return JSONResponse(
            content=response.json(),
            status_code=response.status_code
        )
    except httpx.RequestError as e:
        logger.error("Data processor service error", error=str(e))
        raise HTTPException(status_code=503, detail="Data processing service unavailable")

@app.get("/data/status/{job_id}")
@limiter.limit("30/minute")
async def proxy_data_status(
    job_id: str,
    request: Request,
    user: Dict[str, Any] = Depends(get_current_user)
):
    """Proxy to data processing status endpoint"""
    try:
        response = await gateway.proxy_request(
            service_name="data-processor",
            path=f"/data/status/{job_id}",
            method="GET",
            headers=dict(request.headers)
        )
        
        return JSONResponse(
            content=response.json(),
            status_code=response.status_code
        )
    except httpx.RequestError as e:
        logger.error("Data processor service error", error=str(e))
        raise HTTPException(status_code=503, detail="Data processing service unavailable")

# Analytics Engine Service Proxy
@app.post("/analytics/query")
@limiter.limit("20/minute")
async def proxy_analytics_query(
    request: Request,
    background_tasks: BackgroundTasks,
    user: Dict[str, Any] = Depends(get_current_user)
):
    """Proxy to analytics engine"""
    try:
        body = await request.body()
        response = await gateway.proxy_request(
            service_name="analytics-engine",
            path="/analytics/query",
            method="POST",
            headers=dict(request.headers),
            body=body
        )
        
        # Background audit logging
        background_tasks.add_task(
            log_service_call,
            service="analytics-engine",
            endpoint="/analytics/query",
            user_id=user.get('user_id'),
            status_code=response.status_code
        )
        
        return JSONResponse(
            content=response.json(),
            status_code=response.status_code
        )
    except httpx.RequestError as e:
        logger.error("Analytics engine service error", error=str(e))
        raise HTTPException(status_code=503, detail="Analytics engine service unavailable")

@app.get("/analytics/types")
@limiter.limit("100/minute")
async def proxy_analytics_types(
    request: Request,
    user: Dict[str, Any] = Depends(get_current_user)
):
    """Proxy to analytics types endpoint"""
    try:
        response = await gateway.proxy_request(
            service_name="analytics-engine",
            path="/analytics/types",
            method="GET",
            headers=dict(request.headers)
        )
        
        return JSONResponse(
            content=response.json(),
            status_code=response.status_code
        )
    except httpx.RequestError as e:
        logger.error("Analytics engine service error", error=str(e))
        raise HTTPException(status_code=503, detail="Analytics engine service unavailable")

# Rate limiting status endpoint
@app.get("/rate-limit/status")
async def rate_limit_status(
    request: Request,
    user: Dict[str, Any] = Depends(get_current_user)
):
    """Get rate limiting status for current user"""
    client_ip = get_remote_address(request)
    return {
        "client_ip": gateway.security.hash_sensitive_data(client_ip),
        "rate_limits": {
            "data_processing": "10/minute",
            "analytics_query": "20/minute", 
            "analytics_types": "100/minute"
        }
    }

async def log_service_call(service: str, endpoint: str, user_id: str, status_code: int):
    """Background task for audit logging"""
    try:
        logger.info("Service call audit",
                   service=service,
                   endpoint=endpoint,
                   user_id=gateway.security.hash_sensitive_data(user_id),
                   status_code=status_code,
                   audit=True)
    except Exception as e:
        logger.error("Failed to log service call audit", error=str(e))

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    await gateway.http_client.aclose()

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8000")),
        log_level=os.getenv("LOG_LEVEL", "info").lower(),
        access_log=True
    )
