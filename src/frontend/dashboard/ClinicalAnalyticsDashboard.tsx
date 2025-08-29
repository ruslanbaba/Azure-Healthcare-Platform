# Real-time Clinical Analytics Dashboard
# Advanced healthcare analytics with real-time insights and predictive modeling

import React, { useState, useEffect, useCallback, useMemo } from 'react';
import {
  ChartContainer,
  LineChart,
  AreaChart,
  BarChart,
  ScatterChart,
  PieChart,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
  Line,
  Area,
  Bar,
  Scatter,
  Cell,
  ReferenceLine,
  Brush
} from 'recharts';
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Grid,
  Typography,
  Box,
  Alert,
  AlertTitle,
  Chip,
  Avatar,
  LinearProgress,
  Accordion,
  AccordionSummary,
  AccordionDetails,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  IconButton,
  Badge,
  Fab,
  Drawer,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  Divider,
  Switch,
  FormControlLabel,
  Select,
  MenuItem,
  FormControl,
  InputLabel,
  TextField,
  DatePicker,
  Slider,
  Autocomplete
} from '@mui/material';
import {
  Dashboard as DashboardIcon,
  LocalHospital as HospitalIcon,
  Timeline as TimelineIcon,
  Assessment as AssessmentIcon,
  Warning as WarningIcon,
  CheckCircle as CheckCircleIcon,
  Error as ErrorIcon,
  Info as InfoIcon,
  Refresh as RefreshIcon,
  Settings as SettingsIcon,
  Download as DownloadIcon,
  Share as ShareIcon,
  FilterList as FilterIcon,
  ExpandMore as ExpandMoreIcon,
  Notifications as NotificationsIcon,
  Person as PersonIcon,
  Group as GroupIcon,
  TrendingUp as TrendingUpIcon,
  TrendingDown as TrendingDownIcon,
  Speed as SpeedIcon,
  Security as SecurityIcon,
  HealthAndSafety as HealthIcon,
  Analytics as AnalyticsIcon
} from '@mui/icons-material';
import { useQuery, useMutation, useSubscription } from '@apollo/client';
import { format, subDays, subHours, subMinutes } from 'date-fns';
import { io } from 'socket.io-client';
import { useTheme } from '@mui/material/styles';
import useMediaQuery from '@mui/material/useMediaQuery';

// WebSocket connection for real-time updates
const socket = io(process.env.REACT_APP_WEBSOCKET_URL, {
  auth: {
    token: localStorage.getItem('authToken')
  }
});

// Color palette for clinical data visualization
const CLINICAL_COLORS = {
  critical: '#d32f2f',
  high: '#f57c00',
  medium: '#fbc02d',
  low: '#388e3c',
  normal: '#1976d2',
  excellent: '#4caf50',
  background: '#f5f5f5',
  primary: '#1976d2',
  secondary: '#dc004e',
  accent: '#9c27b0'
};

// Custom hook for real-time clinical data
const useRealTimeClinicalData = (facilityId, timeRange = '24h') => {
  const [data, setData] = useState({
    patientMetrics: {},
    operationalMetrics: {},
    qualityMetrics: {},
    alerts: [],
    predictions: {}
  });
  const [isConnected, setIsConnected] = useState(false);

  useEffect(() => {
    socket.on('connect', () => {
      setIsConnected(true);
      socket.emit('subscribe_clinical_data', { facilityId, timeRange });
    });

    socket.on('disconnect', () => {
      setIsConnected(false);
    });

    socket.on('clinical_data_update', (newData) => {
      setData(prevData => ({
        ...prevData,
        ...newData,
        lastUpdated: new Date()
      }));
    });

    socket.on('clinical_alert', (alert) => {
      setData(prevData => ({
        ...prevData,
        alerts: [alert, ...prevData.alerts.slice(0, 99)] // Keep last 100 alerts
      }));
    });

    return () => {
      socket.off('connect');
      socket.off('disconnect');
      socket.off('clinical_data_update');
      socket.off('clinical_alert');
    };
  }, [facilityId, timeRange]);

  return { data, isConnected };
};

// Key Performance Indicators Component
const ClinicalKPICards = ({ metrics, isConnected }) => {
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down('sm'));

  const kpis = [
    {
      title: 'Active Patients',
      value: metrics.activePatients || 0,
      change: metrics.activePatients_change || 0,
      icon: <PersonIcon />,
      color: CLINICAL_COLORS.primary,
      format: 'number'
    },
    {
      title: 'Average LOS',
      value: metrics.averageLOS || 0,
      change: metrics.averageLOS_change || 0,
      icon: <HospitalIcon />,
      color: CLINICAL_COLORS.secondary,
      format: 'decimal',
      suffix: ' days'
    },
    {
      title: 'Readmission Rate',
      value: metrics.readmissionRate || 0,
      change: metrics.readmissionRate_change || 0,
      icon: <TrendingUpIcon />,
      color: CLINICAL_COLORS.high,
      format: 'percentage'
    },
    {
      title: 'Patient Satisfaction',
      value: metrics.patientSatisfaction || 0,
      change: metrics.patientSatisfaction_change || 0,
      icon: <CheckCircleIcon />,
      color: CLINICAL_COLORS.excellent,
      format: 'percentage'
    },
    {
      title: 'Mortality Rate',
      value: metrics.mortalityRate || 0,
      change: metrics.mortalityRate_change || 0,
      icon: <ErrorIcon />,
      color: CLINICAL_COLORS.critical,
      format: 'percentage'
    },
    {
      title: 'Sepsis Risk Score',
      value: metrics.sepsisRiskScore || 0,
      change: metrics.sepsisRiskScore_change || 0,
      icon: <WarningIcon />,
      color: CLINICAL_COLORS.high,
      format: 'decimal'
    }
  ];

  const formatValue = (value, format, suffix = '') => {
    switch (format) {
      case 'percentage':
        return `${(value * 100).toFixed(1)}%`;
      case 'decimal':
        return `${value.toFixed(1)}${suffix}`;
      case 'number':
        return value.toLocaleString();
      default:
        return value;
    }
  };

  const getChangeColor = (change) => {
    if (change > 0) return CLINICAL_COLORS.excellent;
    if (change < 0) return CLINICAL_COLORS.critical;
    return theme.palette.text.secondary;
  };

  return (
    <Grid container spacing={isMobile ? 1 : 2}>
      {kpis.map((kpi, index) => (
        <Grid item xs={12} sm={6} md={4} lg={2} key={index}>
          <Card 
            elevation={2}
            sx={{ 
              height: '100%',
              background: `linear-gradient(135deg, ${kpi.color}15, ${kpi.color}05)`,
              border: `1px solid ${kpi.color}30`,
              position: 'relative',
              overflow: 'visible'
            }}
          >
            <CardContent sx={{ pb: 1 }}>
              <Box display="flex" alignItems="center" justifyContent="space-between">
                <Avatar 
                  sx={{ 
                    bgcolor: kpi.color, 
                    width: 40, 
                    height: 40 
                  }}
                >
                  {kpi.icon}
                </Avatar>
                <Box display="flex" alignItems="center">
                  <Chip
                    size="small"
                    label={isConnected ? 'LIVE' : 'OFFLINE'}
                    color={isConnected ? 'success' : 'error'}
                    variant="outlined"
                  />
                </Box>
              </Box>
              
              <Typography variant="h4" fontWeight="bold" mt={1}>
                {formatValue(kpi.value, kpi.format, kpi.suffix)}
              </Typography>
              
              <Typography variant="body2" color="text.secondary" noWrap>
                {kpi.title}
              </Typography>
              
              <Box display="flex" alignItems="center" mt={1}>
                {kpi.change !== 0 && (
                  <>
                    {kpi.change > 0 ? 
                      <TrendingUpIcon sx={{ color: getChangeColor(kpi.change), fontSize: 16 }} /> :
                      <TrendingDownIcon sx={{ color: getChangeColor(kpi.change), fontSize: 16 }} />
                    }
                    <Typography 
                      variant="caption" 
                      sx={{ color: getChangeColor(kpi.change), ml: 0.5 }}
                    >
                      {Math.abs(kpi.change).toFixed(1)}%
                    </Typography>
                  </>
                )}
              </Box>
            </CardContent>
          </Card>
        </Grid>
      ))}
    </Grid>
  );
};

// Real-time Patient Flow Chart
const PatientFlowChart = ({ data, timeRange }) => {
  const theme = useTheme();
  
  const patientFlowData = useMemo(() => {
    if (!data.patientFlow) return [];
    
    return data.patientFlow.map(point => ({
      ...point,
      timestamp: format(new Date(point.timestamp), 'HH:mm'),
      admissions: point.admissions || 0,
      discharges: point.discharges || 0,
      transfers: point.transfers || 0,
      currentCensus: point.currentCensus || 0
    }));
  }, [data.patientFlow]);

  return (
    <Card elevation={2}>
      <CardHeader
        title="Patient Flow Analytics"
        subheader={`Real-time patient movement - Last ${timeRange}`}
        action={
          <Box display="flex" gap={1}>
            <Chip label="Real-time" color="success" size="small" />
            <IconButton size="small">
              <RefreshIcon />
            </IconButton>
          </Box>
        }
      />
      <CardContent>
        <ResponsiveContainer width="100%" height={300}>
          <LineChart data={patientFlowData}>
            <CartesianGrid strokeDasharray="3 3" stroke={theme.palette.divider} />
            <XAxis 
              dataKey="timestamp" 
              tick={{ fontSize: 12 }}
              stroke={theme.palette.text.secondary}
            />
            <YAxis 
              tick={{ fontSize: 12 }}
              stroke={theme.palette.text.secondary}
            />
            <Tooltip 
              contentStyle={{
                backgroundColor: theme.palette.background.paper,
                border: `1px solid ${theme.palette.divider}`,
                borderRadius: 4
              }}
            />
            <Legend />
            <Line 
              type="monotone" 
              dataKey="admissions" 
              stroke={CLINICAL_COLORS.primary} 
              strokeWidth={2}
              name="Admissions"
            />
            <Line 
              type="monotone" 
              dataKey="discharges" 
              stroke={CLINICAL_COLORS.excellent} 
              strokeWidth={2}
              name="Discharges"
            />
            <Line 
              type="monotone" 
              dataKey="transfers" 
              stroke={CLINICAL_COLORS.medium} 
              strokeWidth={2}
              name="Transfers"
            />
            <Line 
              type="monotone" 
              dataKey="currentCensus" 
              stroke={CLINICAL_COLORS.secondary} 
              strokeWidth={3}
              name="Current Census"
            />
          </LineChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  );
};

// Clinical Quality Metrics Dashboard
const ClinicalQualityMetrics = ({ data }) => {
  const theme = useTheme();
  
  const qualityMetrics = [
    {
      name: 'Hand Hygiene Compliance',
      value: data.handHygieneCompliance || 0,
      target: 95,
      unit: '%',
      trend: 'up'
    },
    {
      name: 'Medication Error Rate',
      value: data.medicationErrorRate || 0,
      target: 2,
      unit: '%',
      trend: 'down'
    },
    {
      name: 'Fall Prevention Score',
      value: data.fallPreventionScore || 0,
      target: 90,
      unit: '%',
      trend: 'up'
    },
    {
      name: 'Pressure Ulcer Rate',
      value: data.pressureUlcerRate || 0,
      target: 1,
      unit: '%',
      trend: 'down'
    },
    {
      name: 'Infection Control Score',
      value: data.infectionControlScore || 0,
      target: 98,
      unit: '%',
      trend: 'up'
    },
    {
      name: 'Pain Management Score',
      value: data.painManagementScore || 0,
      target: 85,
      unit: '%',
      trend: 'up'
    }
  ];

  const getScoreColor = (value, target, trend) => {
    const isGood = trend === 'up' ? value >= target : value <= target;
    if (isGood) return CLINICAL_COLORS.excellent;
    if (Math.abs(value - target) <= target * 0.1) return CLINICAL_COLORS.medium;
    return CLINICAL_COLORS.critical;
  };

  return (
    <Card elevation={2}>
      <CardHeader
        title="Clinical Quality Indicators"
        subheader="Real-time quality metrics and compliance scores"
        action={
          <Chip label="HIPAA Compliant" color="success" size="small" />
        }
      />
      <CardContent>
        <Grid container spacing={2}>
          {qualityMetrics.map((metric, index) => (
            <Grid item xs={12} sm={6} md={4} key={index}>
              <Box 
                p={2} 
                border={1} 
                borderColor={getScoreColor(metric.value, metric.target, metric.trend)}
                borderRadius={2}
                bgcolor={`${getScoreColor(metric.value, metric.target, metric.trend)}10`}
              >
                <Typography variant="subtitle2" gutterBottom>
                  {metric.name}
                </Typography>
                
                <Box display="flex" alignItems="center" justifyContent="space-between" mb={1}>
                  <Typography variant="h5" fontWeight="bold">
                    {metric.value.toFixed(1)}{metric.unit}
                  </Typography>
                  <Typography variant="caption" color="text.secondary">
                    Target: {metric.target}{metric.unit}
                  </Typography>
                </Box>
                
                <LinearProgress
                  variant="determinate"
                  value={Math.min((metric.value / metric.target) * 100, 100)}
                  sx={{
                    height: 6,
                    borderRadius: 3,
                    backgroundColor: theme.palette.grey[200],
                    '& .MuiLinearProgress-bar': {
                      backgroundColor: getScoreColor(metric.value, metric.target, metric.trend)
                    }
                  }}
                />
                
                <Box display="flex" justifyContent="space-between" mt={1}>
                  <Typography variant="caption">
                    {((metric.value / metric.target) * 100).toFixed(0)}% of target
                  </Typography>
                  <Typography 
                    variant="caption" 
                    color={getScoreColor(metric.value, metric.target, metric.trend)}
                  >
                    {metric.trend === 'up' ? 
                      (metric.value >= metric.target ? '✓ Met' : '⚠ Below') :
                      (metric.value <= metric.target ? '✓ Met' : '⚠ Above')
                    }
                  </Typography>
                </Box>
              </Box>
            </Grid>
          ))}
        </Grid>
      </CardContent>
    </Card>
  );
};

// Real-time Clinical Alerts Component
const ClinicalAlertsPanel = ({ alerts, onAlertAction }) => {
  const [filterSeverity, setFilterSeverity] = useState('all');
  const [expandedAlert, setExpandedAlert] = useState(null);

  const filteredAlerts = useMemo(() => {
    if (filterSeverity === 'all') return alerts;
    return alerts.filter(alert => alert.severity === filterSeverity);
  }, [alerts, filterSeverity]);

  const getSeverityColor = (severity) => {
    switch (severity) {
      case 'critical': return CLINICAL_COLORS.critical;
      case 'high': return CLINICAL_COLORS.high;
      case 'medium': return CLINICAL_COLORS.medium;
      case 'low': return CLINICAL_COLORS.low;
      default: return CLINICAL_COLORS.normal;
    }
  };

  const getSeverityIcon = (severity) => {
    switch (severity) {
      case 'critical': return <ErrorIcon />;
      case 'high': return <WarningIcon />;
      case 'medium': return <InfoIcon />;
      case 'low': return <CheckCircleIcon />;
      default: return <InfoIcon />;
    }
  };

  return (
    <Card elevation={2}>
      <CardHeader
        title={
          <Box display="flex" alignItems="center" gap={1}>
            <NotificationsIcon />
            Clinical Alerts
            <Badge badgeContent={filteredAlerts.length} color="error" />
          </Box>
        }
        action={
          <FormControl size="small" sx={{ minWidth: 120 }}>
            <InputLabel>Severity</InputLabel>
            <Select
              value={filterSeverity}
              onChange={(e) => setFilterSeverity(e.target.value)}
              label="Severity"
            >
              <MenuItem value="all">All</MenuItem>
              <MenuItem value="critical">Critical</MenuItem>
              <MenuItem value="high">High</MenuItem>
              <MenuItem value="medium">Medium</MenuItem>
              <MenuItem value="low">Low</MenuItem>
            </Select>
          </FormControl>
        }
      />
      <CardContent sx={{ maxHeight: 400, overflow: 'auto' }}>
        {filteredAlerts.length === 0 ? (
          <Box textAlign="center" py={4}>
            <CheckCircleIcon sx={{ fontSize: 48, color: CLINICAL_COLORS.excellent, mb: 1 }} />
            <Typography variant="h6" color="text.secondary">
              No active alerts
            </Typography>
          </Box>
        ) : (
          filteredAlerts.map((alert, index) => (
            <Accordion
              key={alert.id || index}
              expanded={expandedAlert === index}
              onChange={(_, isExpanded) => setExpandedAlert(isExpanded ? index : null)}
              sx={{ 
                mb: 1,
                border: `1px solid ${getSeverityColor(alert.severity)}40`,
                '&:before': { display: 'none' }
              }}
            >
              <AccordionSummary expandIcon={<ExpandMoreIcon />}>
                <Box display="flex" alignItems="center" width="100%" gap={2}>
                  <Avatar 
                    sx={{ 
                      bgcolor: getSeverityColor(alert.severity),
                      width: 32,
                      height: 32
                    }}
                  >
                    {getSeverityIcon(alert.severity)}
                  </Avatar>
                  
                  <Box flex={1}>
                    <Typography variant="subtitle2" fontWeight="bold">
                      {alert.title}
                    </Typography>
                    <Typography variant="caption" color="text.secondary">
                      {alert.patient_id} • {format(new Date(alert.timestamp), 'PPp')}
                    </Typography>
                  </Box>
                  
                  <Chip
                    label={alert.severity.toUpperCase()}
                    size="small"
                    sx={{ 
                      bgcolor: getSeverityColor(alert.severity),
                      color: 'white',
                      fontWeight: 'bold'
                    }}
                  />
                </Box>
              </AccordionSummary>
              
              <AccordionDetails>
                <Typography variant="body2" paragraph>
                  {alert.description}
                </Typography>
                
                {alert.vital_signs && (
                  <Box mb={2}>
                    <Typography variant="subtitle2" gutterBottom>
                      Vital Signs:
                    </Typography>
                    <Grid container spacing={1}>
                      {Object.entries(alert.vital_signs).map(([key, value]) => (
                        <Grid item xs={6} sm={3} key={key}>
                          <Paper variant="outlined" sx={{ p: 1, textAlign: 'center' }}>
                            <Typography variant="caption" color="text.secondary">
                              {key.replace('_', ' ').toUpperCase()}
                            </Typography>
                            <Typography variant="h6">
                              {value}
                            </Typography>
                          </Paper>
                        </Grid>
                      ))}
                    </Grid>
                  </Box>
                )}
                
                {alert.recommendations && (
                  <Box mb={2}>
                    <Typography variant="subtitle2" gutterBottom>
                      Recommendations:
                    </Typography>
                    <List dense>
                      {alert.recommendations.map((rec, idx) => (
                        <ListItem key={idx} sx={{ py: 0 }}>
                          <ListItemIcon sx={{ minWidth: 32 }}>
                            <CheckCircleIcon sx={{ fontSize: 16 }} />
                          </ListItemIcon>
                          <ListItemText primary={rec} />
                        </ListItem>
                      ))}
                    </List>
                  </Box>
                )}
                
                <Box display="flex" gap={1} mt={2}>
                  <Chip
                    label="Acknowledge"
                    color="primary"
                    size="small"
                    onClick={() => onAlertAction(alert.id, 'acknowledge')}
                  />
                  <Chip
                    label="Escalate"
                    color="error"
                    size="small"
                    onClick={() => onAlertAction(alert.id, 'escalate')}
                  />
                  <Chip
                    label="Resolve"
                    color="success"
                    size="small"
                    onClick={() => onAlertAction(alert.id, 'resolve')}
                  />
                </Box>
              </AccordionDetails>
            </Accordion>
          ))
        )}
      </CardContent>
    </Card>
  );
};

// Predictive Analytics Component
const PredictiveAnalytics = ({ predictions }) => {
  const theme = useTheme();
  
  const predictionData = useMemo(() => {
    if (!predictions.riskScores) return [];
    
    return predictions.riskScores.map(score => ({
      category: score.category,
      current: score.current,
      predicted: score.predicted,
      confidence: score.confidence
    }));
  }, [predictions.riskScores]);

  return (
    <Card elevation={2}>
      <CardHeader
        title="Predictive Risk Analytics"
        subheader="AI-powered clinical risk predictions"
        action={
          <Chip label="ML Powered" color="primary" size="small" />
        }
      />
      <CardContent>
        <ResponsiveContainer width="100%" height={350}>
          <BarChart data={predictionData}>
            <CartesianGrid strokeDasharray="3 3" stroke={theme.palette.divider} />
            <XAxis 
              dataKey="category" 
              tick={{ fontSize: 12 }}
              angle={-45}
              textAnchor="end"
              height={80}
            />
            <YAxis 
              tick={{ fontSize: 12 }}
              domain={[0, 1]}
              tickFormatter={(value) => `${(value * 100).toFixed(0)}%`}
            />
            <Tooltip 
              formatter={(value, name) => [
                `${(value * 100).toFixed(1)}%`,
                name === 'current' ? 'Current Risk' : 'Predicted Risk'
              ]}
              contentStyle={{
                backgroundColor: theme.palette.background.paper,
                border: `1px solid ${theme.palette.divider}`,
                borderRadius: 4
              }}
            />
            <Legend />
            <Bar 
              dataKey="current" 
              fill={CLINICAL_COLORS.primary} 
              name="Current Risk"
              radius={[2, 2, 0, 0]}
            />
            <Bar 
              dataKey="predicted" 
              fill={CLINICAL_COLORS.secondary} 
              name="Predicted Risk"
              radius={[2, 2, 0, 0]}
            />
          </BarChart>
        </ResponsiveContainer>
        
        <Box mt={2}>
          <Typography variant="subtitle2" gutterBottom>
            Prediction Confidence Levels:
          </Typography>
          <Grid container spacing={1}>
            {predictionData.map((item, index) => (
              <Grid item xs={6} sm={4} key={index}>
                <Box 
                  p={1} 
                  border={1} 
                  borderColor="divider" 
                  borderRadius={1}
                  textAlign="center"
                >
                  <Typography variant="caption" color="text.secondary">
                    {item.category}
                  </Typography>
                  <LinearProgress
                    variant="determinate"
                    value={item.confidence * 100}
                    sx={{ mt: 0.5, mb: 0.5 }}
                  />
                  <Typography variant="caption">
                    {(item.confidence * 100).toFixed(0)}% confidence
                  </Typography>
                </Box>
              </Grid>
            ))}
          </Grid>
        </Box>
      </CardContent>
    </Card>
  );
};

// Main Dashboard Component
const ClinicalAnalyticsDashboard = ({ facilityId = 'facility_001' }) => {
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down('md'));
  
  const [timeRange, setTimeRange] = useState('24h');
  const [selectedDepartment, setSelectedDepartment] = useState('all');
  const [alertsDrawerOpen, setAlertsDrawerOpen] = useState(false);
  const [autoRefresh, setAutoRefresh] = useState(true);
  
  // Real-time data hook
  const { data, isConnected } = useRealTimeClinicalData(facilityId, timeRange);
  
  const handleAlertAction = useCallback((alertId, action) => {
    console.log(`Alert ${alertId} - Action: ${action}`);
    // Implement alert action logic
  }, []);

  const handleRefresh = useCallback(() => {
    socket.emit('request_data_refresh', { facilityId, timeRange });
  }, [facilityId, timeRange]);

  useEffect(() => {
    if (autoRefresh) {
      const interval = setInterval(handleRefresh, 30000); // Refresh every 30 seconds
      return () => clearInterval(interval);
    }
  }, [autoRefresh, handleRefresh]);

  return (
    <Box sx={{ flexGrow: 1, p: isMobile ? 1 : 3 }}>
      {/* Header */}
      <Box display="flex" justifyContent="space-between" alignItems="center" mb={3}>
        <Box>
          <Typography variant="h4" fontWeight="bold" gutterBottom>
            Clinical Analytics Dashboard
          </Typography>
          <Box display="flex" alignItems="center" gap={2}>
            <Chip
              icon={<AnalyticsIcon />}
              label={`Facility: ${facilityId}`}
              color="primary"
              variant="outlined"
            />
            <Chip
              icon={isConnected ? <CheckCircleIcon /> : <ErrorIcon />}
              label={isConnected ? 'Connected' : 'Disconnected'}
              color={isConnected ? 'success' : 'error'}
            />
            <Typography variant="caption" color="text.secondary">
              Last updated: {data.lastUpdated ? format(data.lastUpdated, 'PPp') : 'Never'}
            </Typography>
          </Box>
        </Box>
        
        <Box display="flex" gap={1}>
          <FormControl size="small" sx={{ minWidth: 120 }}>
            <InputLabel>Time Range</InputLabel>
            <Select
              value={timeRange}
              onChange={(e) => setTimeRange(e.target.value)}
              label="Time Range"
            >
              <MenuItem value="1h">Last Hour</MenuItem>
              <MenuItem value="6h">Last 6 Hours</MenuItem>
              <MenuItem value="24h">Last 24 Hours</MenuItem>
              <MenuItem value="7d">Last 7 Days</MenuItem>
            </Select>
          </FormControl>
          
          <FormControlLabel
            control={
              <Switch
                checked={autoRefresh}
                onChange={(e) => setAutoRefresh(e.target.checked)}
                size="small"
              />
            }
            label="Auto-refresh"
          />
          
          <IconButton onClick={handleRefresh} color="primary">
            <RefreshIcon />
          </IconButton>
          
          <IconButton onClick={() => setAlertsDrawerOpen(true)} color="error">
            <Badge badgeContent={data.alerts?.length || 0} color="error">
              <NotificationsIcon />
            </Badge>
          </IconButton>
        </Box>
      </Box>

      {/* KPI Cards */}
      <Box mb={3}>
        <ClinicalKPICards metrics={data.patientMetrics || {}} isConnected={isConnected} />
      </Box>

      {/* Main Content Grid */}
      <Grid container spacing={3}>
        {/* Patient Flow Chart */}
        <Grid item xs={12} lg={8}>
          <PatientFlowChart data={data} timeRange={timeRange} />
        </Grid>
        
        {/* Predictive Analytics */}
        <Grid item xs={12} lg={4}>
          <PredictiveAnalytics predictions={data.predictions || {}} />
        </Grid>
        
        {/* Clinical Quality Metrics */}
        <Grid item xs={12}>
          <ClinicalQualityMetrics data={data.qualityMetrics || {}} />
        </Grid>
      </Grid>

      {/* Alerts Drawer */}
      <Drawer
        anchor="right"
        open={alertsDrawerOpen}
        onClose={() => setAlertsDrawerOpen(false)}
        sx={{
          '& .MuiDrawer-paper': {
            width: isMobile ? '100%' : 500,
            maxWidth: '100vw'
          }
        }}
      >
        <Box sx={{ width: '100%', height: '100%' }}>
          <ClinicalAlertsPanel
            alerts={data.alerts || []}
            onAlertAction={handleAlertAction}
          />
        </Box>
      </Drawer>

      {/* Floating Action Button for Quick Actions */}
      <Fab
        color="primary"
        sx={{ position: 'fixed', bottom: 16, right: 16 }}
        onClick={() => setAlertsDrawerOpen(true)}
      >
        <Badge badgeContent={data.alerts?.length || 0} color="error">
          <DashboardIcon />
        </Badge>
      </Fab>
    </Box>
  );
};

export default ClinicalAnalyticsDashboard;
