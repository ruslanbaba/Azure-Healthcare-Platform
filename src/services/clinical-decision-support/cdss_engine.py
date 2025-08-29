# Intelligent Clinical Decision Support System (CDSS)
# Advanced AI-powered clinical decision making and risk assessment

import os
import asyncio
import logging
import json
from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta
from dataclasses import dataclass
import numpy as np
import pandas as pd
from sklearn.ensemble import IsolationForest, RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
import joblib
import aiohttp
import asyncpg
from azure.storage.blob.aio import BlobServiceClient
from azure.keyvault.secrets import SecretClient
from azure.identity.aio import DefaultAzureCredential
from azure.ai.textanalytics.aio import TextAnalyticsClient
from azure.cognitiveservices.vision.computervision import ComputerVisionClient
from azure.ai.formrecognizer.aio import DocumentAnalysisClient
import redis.asyncio as redis
from prometheus_client import Counter, Histogram, Gauge
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

logger = structlog.get_logger(__name__)

# Prometheus metrics
DECISION_REQUESTS = Counter('cdss_decision_requests_total', 'Total CDSS decision requests', ['decision_type'])
DECISION_LATENCY = Histogram('cdss_decision_latency_seconds', 'CDSS decision latency')
RISK_SCORE_GAUGE = Gauge('cdss_risk_score', 'Current risk score', ['patient_id', 'risk_type'])
MODEL_ACCURACY = Gauge('cdss_model_accuracy', 'Model accuracy score', ['model_type'])

@dataclass
class PatientRiskProfile:
    """Patient risk assessment profile"""
    patient_id: str
    age: int
    gender: str
    medical_history: List[str]
    current_medications: List[str]
    vital_signs: Dict[str, float]
    lab_results: Dict[str, float]
    comorbidities: List[str]
    risk_factors: List[str]
    timestamp: datetime

@dataclass
class ClinicalDecision:
    """Clinical decision recommendation"""
    decision_id: str
    patient_id: str
    decision_type: str
    recommendation: str
    confidence_score: float
    risk_level: str
    supporting_evidence: List[str]
    contraindications: List[str]
    alternative_options: List[str]
    follow_up_required: bool
    urgency_level: str
    created_at: datetime
    expires_at: datetime

@dataclass
class AlertCondition:
    """Clinical alert condition"""
    alert_id: str
    patient_id: str
    alert_type: str
    severity: str
    message: str
    triggered_by: str
    conditions_met: List[str]
    recommended_actions: List[str]
    auto_resolved: bool
    timestamp: datetime

class ClinicalDecisionSupportEngine:
    """Advanced Clinical Decision Support System"""
    
    def __init__(self):
        self.credential = DefaultAzureCredential()
        self.models = {}
        self.scalers = {}
        self.feature_columns = {}
        self.redis_client = None
        self.db_pool = None
        self.blob_client = None
        self.text_analytics_client = None
        self.computer_vision_client = None
        self.document_analysis_client = None
        
        # Clinical thresholds and parameters
        self.vital_sign_thresholds = {
            'systolic_bp': {'critical_high': 180, 'high': 140, 'normal_high': 130, 'normal_low': 90, 'low': 80},
            'diastolic_bp': {'critical_high': 120, 'high': 90, 'normal_high': 85, 'normal_low': 60, 'low': 50},
            'heart_rate': {'critical_high': 120, 'high': 100, 'normal_high': 90, 'normal_low': 60, 'critical_low': 40},
            'temperature': {'critical_high': 40.0, 'high': 38.5, 'normal_high': 37.5, 'normal_low': 36.1, 'critical_low': 35.0},
            'oxygen_saturation': {'critical_low': 85, 'low': 90, 'normal_low': 95, 'normal': 98},
            'respiratory_rate': {'critical_high': 30, 'high': 24, 'normal_high': 20, 'normal_low': 12, 'critical_low': 8}
        }
        
        self.lab_value_thresholds = {
            'glucose': {'critical_high': 400, 'high': 180, 'normal_high': 126, 'normal_low': 70, 'critical_low': 50},
            'creatinine': {'critical_high': 3.0, 'high': 1.5, 'normal_high': 1.2, 'normal_low': 0.6},
            'hemoglobin': {'critical_low': 6.0, 'low': 8.0, 'normal_low': 12.0, 'normal_high': 16.0, 'high': 18.0},
            'white_blood_cells': {'critical_high': 30000, 'high': 15000, 'normal_high': 11000, 'normal_low': 4000, 'critical_low': 1000},
            'platelet_count': {'critical_low': 20000, 'low': 50000, 'normal_low': 150000, 'normal_high': 450000, 'high': 600000}
        }
        
    async def initialize(self):
        """Initialize all Azure services and load ML models"""
        try:
            logger.info("Initializing Clinical Decision Support Engine")
            
            # Initialize Azure services
            await self._initialize_azure_services()
            
            # Load pre-trained ML models
            await self._load_ml_models()
            
            # Initialize database connection
            await self._initialize_database()
            
            # Initialize Redis cache
            await self._initialize_cache()
            
            logger.info("CDSS Engine initialized successfully")
            
        except Exception as e:
            logger.error("Failed to initialize CDSS Engine", error=str(e))
            raise
    
    async def _initialize_azure_services(self):
        """Initialize Azure Cognitive Services"""
        # Get credentials from Key Vault
        key_vault_url = os.getenv('KEY_VAULT_URL')
        secret_client = SecretClient(vault_url=key_vault_url, credential=self.credential)
        
        # Text Analytics for clinical text processing
        text_analytics_key = await secret_client.get_secret("text-analytics-key")
        text_analytics_endpoint = await secret_client.get_secret("text-analytics-endpoint")
        self.text_analytics_client = TextAnalyticsClient(
            endpoint=text_analytics_endpoint.value,
            credential=self.credential
        )
        
        # Computer Vision for medical image analysis
        cv_key = await secret_client.get_secret("computer-vision-key")
        cv_endpoint = await secret_client.get_secret("computer-vision-endpoint")
        self.computer_vision_client = ComputerVisionClient(
            endpoint=cv_endpoint.value,
            credential=self.credential
        )
        
        # Document Analysis for medical records
        doc_analysis_endpoint = await secret_client.get_secret("document-analysis-endpoint")
        self.document_analysis_client = DocumentAnalysisClient(
            endpoint=doc_analysis_endpoint.value,
            credential=self.credential
        )
        
        # Blob Storage for model artifacts
        storage_account_name = os.getenv('STORAGE_ACCOUNT_NAME')
        self.blob_client = BlobServiceClient(
            account_url=f"https://{storage_account_name}.blob.core.windows.net",
            credential=self.credential
        )
    
    async def _load_ml_models(self):
        """Load pre-trained machine learning models"""
        try:
            # Download models from blob storage
            container_name = "ml-models"
            
            model_files = [
                "sepsis_prediction_model.pkl",
                "readmission_risk_model.pkl",
                "medication_interaction_model.pkl",
                "fall_risk_model.pkl",
                "mortality_prediction_model.pkl"
            ]
            
            for model_file in model_files:
                model_name = model_file.replace('.pkl', '').replace('_model', '')
                
                # Download model from blob storage
                blob_client = self.blob_client.get_blob_client(
                    container=container_name,
                    blob=model_file
                )
                
                model_data = await blob_client.download_blob()
                model_bytes = await model_data.readall()
                
                # Load model using joblib
                import io
                model = joblib.load(io.BytesIO(model_bytes))
                self.models[model_name] = model
                
                # Load corresponding scaler
                scaler_file = model_file.replace('_model.pkl', '_scaler.pkl')
                scaler_blob = self.blob_client.get_blob_client(
                    container=container_name,
                    blob=scaler_file
                )
                
                scaler_data = await scaler_blob.download_blob()
                scaler_bytes = await scaler_data.readall()
                scaler = joblib.load(io.BytesIO(scaler_bytes))
                self.scalers[model_name] = scaler
                
                logger.info(f"Loaded model: {model_name}")
                
        except Exception as e:
            logger.error("Failed to load ML models", error=str(e))
            raise
    
    async def _initialize_database(self):
        """Initialize PostgreSQL database connection"""
        db_host = os.getenv('DB_HOST')
        db_name = os.getenv('DB_NAME')
        db_user = os.getenv('DB_USER')
        db_password = os.getenv('DB_PASSWORD')
        
        self.db_pool = await asyncpg.create_pool(
            host=db_host,
            database=db_name,
            user=db_user,
            password=db_password,
            min_size=5,
            max_size=20,
            ssl='require'
        )
    
    async def _initialize_cache(self):
        """Initialize Redis cache connection"""
        redis_host = os.getenv('REDIS_HOST')
        redis_password = os.getenv('REDIS_PASSWORD')
        
        self.redis_client = redis.Redis(
            host=redis_host,
            port=6380,
            password=redis_password,
            ssl=True,
            decode_responses=True
        )
    
    @DECISION_LATENCY.time()
    async def generate_clinical_decision(self, patient_risk_profile: PatientRiskProfile) -> ClinicalDecision:
        """Generate comprehensive clinical decision recommendation"""
        DECISION_REQUESTS.labels(decision_type='comprehensive').inc()
        
        try:
            logger.info("Generating clinical decision", patient_id=patient_risk_profile.patient_id)
            
            # Check cache first
            cache_key = f"cdss:decision:{patient_risk_profile.patient_id}"
            cached_decision = await self.redis_client.get(cache_key)
            
            if cached_decision:
                logger.info("Using cached decision", patient_id=patient_risk_profile.patient_id)
                return ClinicalDecision(**json.loads(cached_decision))
            
            # Perform comprehensive risk assessment
            risk_scores = await self._calculate_risk_scores(patient_risk_profile)
            
            # Generate specific recommendations
            recommendations = await self._generate_recommendations(patient_risk_profile, risk_scores)
            
            # Check for contraindications
            contraindications = await self._check_contraindications(patient_risk_profile)
            
            # Determine urgency level
            urgency_level = self._determine_urgency(risk_scores)
            
            # Create clinical decision
            decision = ClinicalDecision(
                decision_id=f"cdss_{patient_risk_profile.patient_id}_{int(datetime.now().timestamp())}",
                patient_id=patient_risk_profile.patient_id,
                decision_type="comprehensive_assessment",
                recommendation=recommendations['primary'],
                confidence_score=recommendations['confidence'],
                risk_level=self._categorize_risk_level(risk_scores),
                supporting_evidence=recommendations['evidence'],
                contraindications=contraindications,
                alternative_options=recommendations['alternatives'],
                follow_up_required=self._requires_follow_up(risk_scores),
                urgency_level=urgency_level,
                created_at=datetime.now(),
                expires_at=datetime.now() + timedelta(hours=24)
            )
            
            # Cache the decision
            await self.redis_client.setex(
                cache_key,
                3600,  # 1 hour cache
                json.dumps(decision.__dict__, default=str)
            )
            
            # Store in database
            await self._store_decision(decision)
            
            # Update risk score metrics
            for risk_type, score in risk_scores.items():
                RISK_SCORE_GAUGE.labels(
                    patient_id=patient_risk_profile.patient_id,
                    risk_type=risk_type
                ).set(score)
            
            logger.info("Generated clinical decision", 
                       patient_id=patient_risk_profile.patient_id,
                       decision_id=decision.decision_id,
                       confidence=decision.confidence_score)
            
            return decision
            
        except Exception as e:
            logger.error("Failed to generate clinical decision", 
                        patient_id=patient_risk_profile.patient_id,
                        error=str(e))
            raise
    
    async def _calculate_risk_scores(self, profile: PatientRiskProfile) -> Dict[str, float]:
        """Calculate various risk scores using ML models"""
        risk_scores = {}
        
        try:
            # Prepare feature vector
            features = self._extract_features(profile)
            
            # Sepsis risk prediction
            if 'sepsis_prediction' in self.models:
                sepsis_features = self.scalers['sepsis_prediction'].transform([features['sepsis']])
                sepsis_risk = self.models['sepsis_prediction'].predict_proba(sepsis_features)[0][1]
                risk_scores['sepsis'] = float(sepsis_risk)
            
            # Readmission risk
            if 'readmission_risk' in self.models:
                readmission_features = self.scalers['readmission_risk'].transform([features['readmission']])
                readmission_risk = self.models['readmission_risk'].predict_proba(readmission_features)[0][1]
                risk_scores['readmission'] = float(readmission_risk)
            
            # Fall risk
            if 'fall_risk' in self.models:
                fall_features = self.scalers['fall_risk'].transform([features['fall']])
                fall_risk = self.models['fall_risk'].predict_proba(fall_features)[0][1]
                risk_scores['fall'] = float(fall_risk)
            
            # Mortality prediction
            if 'mortality_prediction' in self.models:
                mortality_features = self.scalers['mortality_prediction'].transform([features['mortality']])
                mortality_risk = self.models['mortality_prediction'].predict_proba(mortality_features)[0][1]
                risk_scores['mortality'] = float(mortality_risk)
            
            # Drug interaction risk
            drug_interaction_risk = await self._calculate_drug_interaction_risk(profile.current_medications)
            risk_scores['drug_interaction'] = drug_interaction_risk
            
            return risk_scores
            
        except Exception as e:
            logger.error("Failed to calculate risk scores", error=str(e))
            return {}
    
    def _extract_features(self, profile: PatientRiskProfile) -> Dict[str, List[float]]:
        """Extract features for different ML models"""
        base_features = [
            profile.age,
            1 if profile.gender.lower() == 'male' else 0,
            len(profile.medical_history),
            len(profile.current_medications),
            len(profile.comorbidities)
        ]
        
        # Vital signs features
        vital_features = [
            profile.vital_signs.get('systolic_bp', 120),
            profile.vital_signs.get('diastolic_bp', 80),
            profile.vital_signs.get('heart_rate', 70),
            profile.vital_signs.get('temperature', 37.0),
            profile.vital_signs.get('oxygen_saturation', 98),
            profile.vital_signs.get('respiratory_rate', 16)
        ]
        
        # Lab results features
        lab_features = [
            profile.lab_results.get('glucose', 100),
            profile.lab_results.get('creatinine', 1.0),
            profile.lab_results.get('hemoglobin', 14.0),
            profile.lab_results.get('white_blood_cells', 7000),
            profile.lab_results.get('platelet_count', 250000)
        ]
        
        return {
            'sepsis': base_features + vital_features + lab_features,
            'readmission': base_features + [len(profile.medical_history)],
            'fall': base_features + vital_features[:3],  # BP and HR most relevant
            'mortality': base_features + vital_features + lab_features
        }
    
    async def _calculate_drug_interaction_risk(self, medications: List[str]) -> float:
        """Calculate drug interaction risk score"""
        if len(medications) < 2:
            return 0.0
        
        # High-risk drug combinations (simplified for demo)
        high_risk_combinations = {
            ('warfarin', 'aspirin'): 0.8,
            ('digoxin', 'quinidine'): 0.9,
            ('phenytoin', 'warfarin'): 0.7,
            ('metformin', 'contrast_dye'): 0.6
        }
        
        max_risk = 0.0
        for i, med1 in enumerate(medications):
            for med2 in medications[i+1:]:
                combination = tuple(sorted([med1.lower(), med2.lower()]))
                risk = high_risk_combinations.get(combination, 0.1)
                max_risk = max(max_risk, risk)
        
        return max_risk
    
    async def _generate_recommendations(self, profile: PatientRiskProfile, risk_scores: Dict[str, float]) -> Dict[str, Any]:
        """Generate clinical recommendations based on risk assessment"""
        recommendations = {
            'primary': '',
            'alternatives': [],
            'evidence': [],
            'confidence': 0.0
        }
        
        # Determine primary recommendation based on highest risk
        if not risk_scores:
            recommendations['primary'] = "Continue standard care monitoring"
            recommendations['confidence'] = 0.5
            return recommendations
        
        max_risk_type = max(risk_scores, key=risk_scores.get)
        max_risk_score = risk_scores[max_risk_type]
        
        if max_risk_type == 'sepsis' and max_risk_score > 0.7:
            recommendations['primary'] = "Immediate sepsis protocol initiation recommended"
            recommendations['alternatives'] = [
                "Broad-spectrum antibiotic therapy",
                "Fluid resuscitation",
                "Lactate monitoring"
            ]
            recommendations['evidence'] = [
                f"Sepsis risk score: {max_risk_score:.2f}",
                "Elevated vital signs consistent with SIRS criteria"
            ]
            recommendations['confidence'] = max_risk_score
        
        elif max_risk_type == 'fall' and max_risk_score > 0.6:
            recommendations['primary'] = "Fall prevention measures implementation"
            recommendations['alternatives'] = [
                "Bed alarm activation",
                "Physical therapy consultation",
                "Medication review for sedating effects"
            ]
            recommendations['evidence'] = [
                f"Fall risk score: {max_risk_score:.2f}",
                "Multiple risk factors present"
            ]
            recommendations['confidence'] = max_risk_score
        
        elif max_risk_type == 'drug_interaction' and max_risk_score > 0.5:
            recommendations['primary'] = "Medication review and adjustment required"
            recommendations['alternatives'] = [
                "Pharmacist consultation",
                "Alternative medication selection",
                "Enhanced monitoring protocols"
            ]
            recommendations['evidence'] = [
                f"Drug interaction risk: {max_risk_score:.2f}",
                "Multiple medications with potential interactions"
            ]
            recommendations['confidence'] = max_risk_score
        
        else:
            recommendations['primary'] = "Continue current care plan with routine monitoring"
            recommendations['confidence'] = 1.0 - max_risk_score
        
        return recommendations
    
    async def _check_contraindications(self, profile: PatientRiskProfile) -> List[str]:
        """Check for contraindications based on patient profile"""
        contraindications = []
        
        # Check age-related contraindications
        if profile.age > 65:
            contraindications.append("Consider age-adjusted dosing for medications")
        
        # Check for specific medical conditions
        high_risk_conditions = ['renal_failure', 'liver_disease', 'heart_failure']
        for condition in profile.medical_history:
            if any(risk_condition in condition.lower() for risk_condition in high_risk_conditions):
                contraindications.append(f"Contraindication due to {condition}")
        
        # Check vital sign abnormalities
        if profile.vital_signs.get('systolic_bp', 120) > 180:
            contraindications.append("Severe hypertension - avoid vasoconstrictors")
        
        if profile.vital_signs.get('heart_rate', 70) > 120:
            contraindications.append("Tachycardia - avoid stimulants")
        
        return contraindications
    
    def _determine_urgency(self, risk_scores: Dict[str, float]) -> str:
        """Determine urgency level based on risk scores"""
        if not risk_scores:
            return "routine"
        
        max_risk = max(risk_scores.values())
        
        if max_risk > 0.8:
            return "critical"
        elif max_risk > 0.6:
            return "urgent"
        elif max_risk > 0.4:
            return "priority"
        else:
            return "routine"
    
    def _categorize_risk_level(self, risk_scores: Dict[str, float]) -> str:
        """Categorize overall risk level"""
        if not risk_scores:
            return "low"
        
        avg_risk = sum(risk_scores.values()) / len(risk_scores)
        
        if avg_risk > 0.7:
            return "high"
        elif avg_risk > 0.4:
            return "moderate"
        else:
            return "low"
    
    def _requires_follow_up(self, risk_scores: Dict[str, float]) -> bool:
        """Determine if follow-up is required"""
        if not risk_scores:
            return False
        
        return any(score > 0.5 for score in risk_scores.values())
    
    async def _store_decision(self, decision: ClinicalDecision):
        """Store clinical decision in database"""
        try:
            query = """
                INSERT INTO clinical_decisions 
                (decision_id, patient_id, decision_type, recommendation, confidence_score, 
                 risk_level, supporting_evidence, contraindications, alternative_options, 
                 follow_up_required, urgency_level, created_at, expires_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
            """
            
            async with self.db_pool.acquire() as conn:
                await conn.execute(
                    query,
                    decision.decision_id,
                    decision.patient_id,
                    decision.decision_type,
                    decision.recommendation,
                    decision.confidence_score,
                    decision.risk_level,
                    json.dumps(decision.supporting_evidence),
                    json.dumps(decision.contraindications),
                    json.dumps(decision.alternative_options),
                    decision.follow_up_required,
                    decision.urgency_level,
                    decision.created_at,
                    decision.expires_at
                )
                
        except Exception as e:
            logger.error("Failed to store decision", decision_id=decision.decision_id, error=str(e))
    
    async def generate_clinical_alerts(self, profile: PatientRiskProfile) -> List[AlertCondition]:
        """Generate clinical alerts based on patient condition"""
        alerts = []
        
        try:
            # Vital signs alerts
            vital_alerts = self._check_vital_sign_alerts(profile)
            alerts.extend(vital_alerts)
            
            # Lab value alerts
            lab_alerts = self._check_lab_value_alerts(profile)
            alerts.extend(lab_alerts)
            
            # Medication alerts
            med_alerts = await self._check_medication_alerts(profile)
            alerts.extend(med_alerts)
            
            # Store alerts in database
            for alert in alerts:
                await self._store_alert(alert)
            
            return alerts
            
        except Exception as e:
            logger.error("Failed to generate clinical alerts", 
                        patient_id=profile.patient_id, error=str(e))
            return []
    
    def _check_vital_sign_alerts(self, profile: PatientRiskProfile) -> List[AlertCondition]:
        """Check for vital sign-based alerts"""
        alerts = []
        
        for vital_sign, value in profile.vital_signs.items():
            if vital_sign in self.vital_sign_thresholds:
                thresholds = self.vital_sign_thresholds[vital_sign]
                
                severity = None
                message = None
                
                if 'critical_high' in thresholds and value >= thresholds['critical_high']:
                    severity = "critical"
                    message = f"Critical high {vital_sign}: {value}"
                elif 'critical_low' in thresholds and value <= thresholds['critical_low']:
                    severity = "critical"
                    message = f"Critical low {vital_sign}: {value}"
                elif 'high' in thresholds and value >= thresholds['high']:
                    severity = "high"
                    message = f"High {vital_sign}: {value}"
                elif 'low' in thresholds and value <= thresholds['low']:
                    severity = "high"
                    message = f"Low {vital_sign}: {value}"
                
                if severity:
                    alert = AlertCondition(
                        alert_id=f"vital_{profile.patient_id}_{vital_sign}_{int(datetime.now().timestamp())}",
                        patient_id=profile.patient_id,
                        alert_type="vital_signs",
                        severity=severity,
                        message=message,
                        triggered_by=vital_sign,
                        conditions_met=[f"{vital_sign} = {value}"],
                        recommended_actions=self._get_vital_sign_actions(vital_sign, severity),
                        auto_resolved=False,
                        timestamp=datetime.now()
                    )
                    alerts.append(alert)
        
        return alerts
    
    def _check_lab_value_alerts(self, profile: PatientRiskProfile) -> List[AlertCondition]:
        """Check for lab value-based alerts"""
        alerts = []
        
        for lab_test, value in profile.lab_results.items():
            if lab_test in self.lab_value_thresholds:
                thresholds = self.lab_value_thresholds[lab_test]
                
                severity = None
                message = None
                
                if 'critical_high' in thresholds and value >= thresholds['critical_high']:
                    severity = "critical"
                    message = f"Critical high {lab_test}: {value}"
                elif 'critical_low' in thresholds and value <= thresholds['critical_low']:
                    severity = "critical"
                    message = f"Critical low {lab_test}: {value}"
                elif 'high' in thresholds and value >= thresholds['high']:
                    severity = "high"
                    message = f"High {lab_test}: {value}"
                elif 'low' in thresholds and value <= thresholds['low']:
                    severity = "high"
                    message = f"Low {lab_test}: {value}"
                
                if severity:
                    alert = AlertCondition(
                        alert_id=f"lab_{profile.patient_id}_{lab_test}_{int(datetime.now().timestamp())}",
                        patient_id=profile.patient_id,
                        alert_type="laboratory",
                        severity=severity,
                        message=message,
                        triggered_by=lab_test,
                        conditions_met=[f"{lab_test} = {value}"],
                        recommended_actions=self._get_lab_value_actions(lab_test, severity),
                        auto_resolved=False,
                        timestamp=datetime.now()
                    )
                    alerts.append(alert)
        
        return alerts
    
    async def _check_medication_alerts(self, profile: PatientRiskProfile) -> List[AlertCondition]:
        """Check for medication-related alerts"""
        alerts = []
        
        # Check for drug interactions
        interaction_risk = await self._calculate_drug_interaction_risk(profile.current_medications)
        
        if interaction_risk > 0.5:
            alert = AlertCondition(
                alert_id=f"med_{profile.patient_id}_interaction_{int(datetime.now().timestamp())}",
                patient_id=profile.patient_id,
                alert_type="medication",
                severity="high" if interaction_risk > 0.7 else "medium",
                message=f"Potential drug interaction detected (risk: {interaction_risk:.2f})",
                triggered_by="drug_interaction_analysis",
                conditions_met=[f"Interaction risk score: {interaction_risk:.2f}"],
                recommended_actions=[
                    "Review medication list with pharmacist",
                    "Consider alternative medications",
                    "Implement enhanced monitoring"
                ],
                auto_resolved=False,
                timestamp=datetime.now()
            )
            alerts.append(alert)
        
        return alerts
    
    def _get_vital_sign_actions(self, vital_sign: str, severity: str) -> List[str]:
        """Get recommended actions for vital sign alerts"""
        actions = {
            'systolic_bp': [
                "Repeat blood pressure measurement",
                "Assess for hypertensive emergency",
                "Consider antihypertensive therapy"
            ],
            'heart_rate': [
                "Obtain 12-lead ECG",
                "Assess hemodynamic stability",
                "Consider cardiac monitoring"
            ],
            'temperature': [
                "Investigate infection source",
                "Consider blood cultures",
                "Implement fever management"
            ],
            'oxygen_saturation': [
                "Administer supplemental oxygen",
                "Assess respiratory status",
                "Consider arterial blood gas"
            ]
        }
        
        return actions.get(vital_sign, ["Notify physician immediately"])
    
    def _get_lab_value_actions(self, lab_test: str, severity: str) -> List[str]:
        """Get recommended actions for lab value alerts"""
        actions = {
            'glucose': [
                "Check point-of-care glucose",
                "Assess for diabetic emergency",
                "Review insulin/diabetes medications"
            ],
            'creatinine': [
                "Assess kidney function",
                "Review nephrotoxic medications",
                "Consider nephrology consultation"
            ],
            'hemoglobin': [
                "Assess for bleeding",
                "Consider transfusion if indicated",
                "Investigate cause of anemia"
            ]
        }
        
        return actions.get(lab_test, ["Notify physician immediately"])
    
    async def _store_alert(self, alert: AlertCondition):
        """Store clinical alert in database"""
        try:
            query = """
                INSERT INTO clinical_alerts 
                (alert_id, patient_id, alert_type, severity, message, triggered_by,
                 conditions_met, recommended_actions, auto_resolved, timestamp)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            """
            
            async with self.db_pool.acquire() as conn:
                await conn.execute(
                    query,
                    alert.alert_id,
                    alert.patient_id,
                    alert.alert_type,
                    alert.severity,
                    alert.message,
                    alert.triggered_by,
                    json.dumps(alert.conditions_met),
                    json.dumps(alert.recommended_actions),
                    alert.auto_resolved,
                    alert.timestamp
                )
                
        except Exception as e:
            logger.error("Failed to store alert", alert_id=alert.alert_id, error=str(e))
    
    async def cleanup(self):
        """Cleanup resources"""
        if self.redis_client:
            await self.redis_client.close()
        
        if self.db_pool:
            await self.db_pool.close()
        
        if self.blob_client:
            await self.blob_client.close()
        
        if self.text_analytics_client:
            await self.text_analytics_client.close()
        
        if self.document_analysis_client:
            await self.document_analysis_client.close()

# Example usage and testing
async def main():
    """Example usage of the Clinical Decision Support System"""
    cdss = ClinicalDecisionSupportEngine()
    
    try:
        await cdss.initialize()
        
        # Example patient profile
        patient_profile = PatientRiskProfile(
            patient_id="P123456",
            age=65,
            gender="male",
            medical_history=["diabetes", "hypertension", "coronary_artery_disease"],
            current_medications=["metformin", "lisinopril", "aspirin", "atorvastatin"],
            vital_signs={
                "systolic_bp": 165,
                "diastolic_bp": 95,
                "heart_rate": 88,
                "temperature": 37.2,
                "oxygen_saturation": 96,
                "respiratory_rate": 18
            },
            lab_results={
                "glucose": 145,
                "creatinine": 1.3,
                "hemoglobin": 12.1,
                "white_blood_cells": 8500,
                "platelet_count": 225000
            },
            comorbidities=["type2_diabetes", "essential_hypertension"],
            risk_factors=["smoking_history", "family_history_cad"],
            timestamp=datetime.now()
        )
        
        # Generate clinical decision
        decision = await cdss.generate_clinical_decision(patient_profile)
        print(f"Clinical Decision: {decision.recommendation}")
        print(f"Confidence: {decision.confidence_score:.2f}")
        print(f"Risk Level: {decision.risk_level}")
        print(f"Urgency: {decision.urgency_level}")
        
        # Generate clinical alerts
        alerts = await cdss.generate_clinical_alerts(patient_profile)
        print(f"Generated {len(alerts)} clinical alerts")
        
        for alert in alerts:
            print(f"Alert: {alert.message} (Severity: {alert.severity})")
        
    finally:
        await cdss.cleanup()

if __name__ == "__main__":
    asyncio.run(main())
