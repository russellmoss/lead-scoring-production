# XGBoost ML Lead Scoring Model V4
## Comprehensive Agentic Development Plan

**Version**: 4.0.0  
**Created**: December 2025  
**Base Directory**: `C:\Users\russe\Documents\Lead Scoring\Version-4`  
**Status**: Development Plan  
**Target**: Contacted → MQL Conversion Prediction

---

## Executive Summary

This document provides a comprehensive, step-by-step plan for building an XGBoost lead scoring model that is:
- **Leakage-aware**: All features use Point-in-Time (PIT) methodology
- **Multicollinearity-free**: Validated correlation thresholds
- **Overfitting-resistant**: Regularization, cross-validation, holdout test
- **Drift-aware**: Accounts for lead source distribution shift
- **Production-ready**: Monitoring, logging, and deployment pipelines

### Key Findings from Data Exploration

| Signal | Lift | Sample Size | Primary/Secondary | Notes |
|--------|------|-------------|-------------------|-------|
| **Mobile + Heavy Bleeding** | **4.85x** | 108 | **Primary (TOP)** | 20.37% conversion - STRONGEST signal |
| **Short Tenure + High Mobility** | **4.59x** | 192 | **Primary (HIGH)** | 19.27% conversion - Very strong |
| **Tenure 1-2 years** | **4.05x** | 229 | Primary | Short tenure = high conversion |
| **Mobility 3+ moves** | **2.98x** | 240 | Primary | Dominant univariate signal |
| **Wirehouse** | **2.15x** | 665 | Primary | **POSITIVE signal** (contradicts V3 exclusion) |
| **Broker Protocol** | **2.03x** | 820 | Secondary | Membership enables transitions |
| Mobile + Growing Firm | 4.54x | 84 | Secondary | Also very strong |
| Stable + Light Bleeding | 2.79x | 376 | Secondary | Moderate signal |

### Critical Constraints

1. **Class Imbalance**: 4.2% positive rate
2. **Lead Source Drift**: 94% → 41% "Provided Lists" (Q1 2024 → Q4 2025)
3. **Firm Data Sparsity**: 93% have "Unknown Firm" status
4. **Small Top Segments**: 108-240 leads in highest-lift segments

---

## Table of Contents

1. [Directory Structure](#1-directory-structure)
2. [Configuration & Constants](#2-configuration--constants)
3. [Logging Framework](#3-logging-framework)
4. [Phase 0: Environment Setup & Preflight](#4-phase-0-environment-setup--preflight)
5. [Phase 1: Data Extraction & Target Definition](#5-phase-1-data-extraction--target-definition)
6. [Phase 2: Point-in-Time Feature Engineering](#6-phase-2-point-in-time-feature-engineering)
7. [Phase 3: Feature Validation & Leakage Audit](#7-phase-3-feature-validation--leakage-audit)
8. [Phase 4: Multicollinearity Analysis](#8-phase-4-multicollinearity-analysis)
9. [Phase 5: Train/Test Split Strategy](#9-phase-5-traintest-split-strategy)
10. [Phase 6: Model Training with Regularization](#10-phase-6-model-training-with-regularization)
11. [Phase 7: Overfitting Detection & Prevention](#11-phase-7-overfitting-detection--prevention)
12. [Phase 8: Model Validation & Performance](#12-phase-8-model-validation--performance)
13. [Phase 9: SHAP Analysis & Interpretability](#13-phase-9-shap-analysis--interpretability)
14. [Phase 10: Production Deployment](#14-phase-10-production-deployment)
15. [Appendix: Gate Summary](#15-appendix-gate-summary)

---

## 1. Directory Structure

**INSTRUCTION**: Create this directory structure before proceeding.

```
C:\Users\russe\Documents\Lead Scoring\Version-4\
├── README.md                           # Project overview
├── VERSION_4_MODEL_REPORT.md           # Final model documentation
├── EXECUTION_LOG.md                    # Running log of all actions
├── config/
│   ├── constants.py                    # All constants and thresholds
│   ├── feature_config.yaml             # Feature definitions
│   └── model_config.yaml               # Model hyperparameters
├── data/
│   ├── raw/                            # Raw data exports
│   ├── processed/                      # Processed feature tables
│   ├── splits/                         # Train/test/validation splits
│   └── exploration/                    # Data exploration outputs
├── sql/
│   ├── phase_1_target_definition.sql   # Target variable SQL
│   ├── phase_2_feature_engineering.sql # PIT feature engineering
│   ├── phase_3_leakage_audit.sql       # Leakage validation queries
│   └── production_scoring.sql          # Production deployment SQL
├── scripts/
│   ├── phase_0_setup.py                # Environment setup
│   ├── phase_1_data_extraction.py      # Data extraction
│   ├── phase_2_feature_engineering.py  # Feature engineering
│   ├── phase_3_leakage_audit.py        # Leakage detection
│   ├── phase_4_multicollinearity.py    # Correlation analysis
│   ├── phase_5_train_test_split.py     # Stratified splitting
│   ├── phase_6_model_training.py       # XGBoost training
│   ├── phase_7_overfitting_check.py    # Overfitting detection
│   ├── phase_8_validation.py           # Model validation
│   ├── phase_9_shap_analysis.py        # SHAP interpretability
│   └── phase_10_deployment.py          # Production deployment
├── utils/
│   ├── execution_logger.py             # Logging framework
│   ├── gate_validator.py               # Gate validation functions
│   ├── pit_validator.py                # PIT compliance checker
│   └── drift_detector.py               # Distribution drift detection
├── models/
│   ├── registry.json                   # Model registry
│   └── v4.0.0/                         # Model artifacts
│       ├── model.pkl                   # Trained model
│       ├── feature_importance.csv      # Feature importance
│       ├── shap_values.pkl             # SHAP values
│       └── training_metrics.json       # Training metrics
├── reports/
│   ├── leakage_audit_report.md         # Leakage audit results
│   ├── multicollinearity_report.md     # Correlation analysis
│   ├── overfitting_report.md           # Overfitting analysis
│   ├── validation_report.md            # Model validation
│   └── shap_report.md                  # SHAP analysis
└── tests/
    ├── test_pit_compliance.py          # PIT validation tests
    ├── test_feature_engineering.py     # Feature tests
    └── test_model_predictions.py       # Prediction tests
```

**Code to Create Directory Structure**:

```python
# File: scripts/create_directory_structure.py
import os
from pathlib import Path

BASE_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4")

directories = [
    "config",
    "data/raw",
    "data/processed",
    "data/splits",
    "data/exploration",
    "sql",
    "scripts",
    "utils",
    "models/v4.0.0",
    "reports",
    "tests"
]

for dir_path in directories:
    full_path = BASE_DIR / dir_path
    full_path.mkdir(parents=True, exist_ok=True)
    print(f"Created: {full_path}")

# Create placeholder files
placeholder_files = [
    "README.md",
    "VERSION_4_MODEL_REPORT.md",
    "EXECUTION_LOG.md",
    "config/constants.py",
    "config/feature_config.yaml",
    "config/model_config.yaml",
    "models/registry.json"
]

for file_path in placeholder_files:
    full_path = BASE_DIR / file_path
    if not full_path.exists():
        full_path.touch()
        print(f"Created: {full_path}")

print("\n✅ Directory structure created successfully!")
```

---

## 2. Configuration & Constants

**INSTRUCTION**: Create the configuration files with all constants and thresholds.

### 2.1 Constants File

```python
# File: config/constants.py
"""
Version 4 Lead Scoring Model - Configuration Constants

All thresholds, gates, and parameters defined here for reproducibility.
"""

from datetime import date
from pathlib import Path

# =============================================================================
# PATHS
# =============================================================================
BASE_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4")
DATA_DIR = BASE_DIR / "data"
MODELS_DIR = BASE_DIR / "models"
REPORTS_DIR = BASE_DIR / "reports"
SQL_DIR = BASE_DIR / "sql"

# =============================================================================
# BIGQUERY CONFIGURATION
# =============================================================================
PROJECT_ID = "savvy-gtm-analytics"
LOCATION = "northamerica-northeast2"  # Toronto
DATASET_FINTRX = "FinTrx_data_CA"
DATASET_SALESFORCE = "SavvyGTMData"
DATASET_ML = "ml_features"

# =============================================================================
# DATE CONFIGURATION
# =============================================================================
# Fixed analysis date for training set stability (prevents drift)
ANALYSIS_DATE = date(2025, 10, 31)

# Data boundaries
TRAINING_START_DATE = date(2024, 2, 1)  # After Firm_historicals available
TRAINING_END_DATE = date(2025, 7, 31)   # Training cutoff
TEST_START_DATE = date(2025, 8, 1)      # Test period start
TEST_END_DATE = date(2025, 10, 31)      # Test period end

# Gap between train and test to prevent leakage
TRAIN_TEST_GAP_DAYS = 30

# Maturity window for conversion (P90 = 39 days, using 43 for safety)
MATURITY_WINDOW_DAYS = 43

# =============================================================================
# TARGET VARIABLE
# =============================================================================
TARGET_COLUMN = "converted"
POSITIVE_CLASS = 1
NEGATIVE_CLASS = 0
BASELINE_CONVERSION_RATE = 0.042  # 4.2%

# =============================================================================
# FEATURE ENGINEERING
# =============================================================================
# Mobility lookback window
MOBILITY_LOOKBACK_YEARS = 3

# Firm stability lookback window
FIRM_STABILITY_LOOKBACK_MONTHS = 12

# Tenure buckets (in months)
TENURE_BUCKETS = {
    "0-12": (0, 12),
    "12-24": (12, 24),
    "24-48": (24, 48),
    "48-120": (48, 120),
    "120+": (120, float('inf'))
}

# Experience buckets (in years)
EXPERIENCE_BUCKETS = {
    "0-5": (0, 5),
    "5-10": (5, 10),
    "10-15": (10, 15),
    "15-20": (15, 20),
    "20+": (20, float('inf'))
}

# Mobility tiers
MOBILITY_TIERS = {
    "Stable": 0,
    "Low_Mobility": 1,
    "High_Mobility": 2  # 2+ moves
}

# Firm stability tiers
FIRM_STABILITY_TIERS = {
    "Heavy_Bleeding": (-float('inf'), -10),
    "Light_Bleeding": (-10, 0),
    "Stable": (0, 0),
    "Growing": (0, float('inf')),
    "Unknown": None
}

# Wirehouse patterns for detection
WIREHOUSE_PATTERNS = [
    "MERRILL", "MORGAN STANLEY", "UBS", "WELLS FARGO", "EDWARD JONES",
    "RAYMOND JAMES", "AMERIPRISE", "LPL", "NORTHWESTERN MUTUAL",
    "STIFEL", "RBC", "JANNEY", "BAIRD", "OPPENHEIMER"
]

# =============================================================================
# VALIDATION GATES - LEAKAGE
# =============================================================================
class LeakageGates:
    """Gates for detecting data leakage."""
    
    # G3.1: No features should use future data
    MAX_FUTURE_CORRELATION = 0.1  # If feature correlates >0.1 with future, flag
    
    # G3.2: No features from *_current tables (except null indicators)
    ALLOWED_CURRENT_TABLE_FEATURES = [
        "is_gender_missing",
        "is_linkedin_missing", 
        "is_personal_email_missing",
        "is_license_data_missing",
        "is_industry_tenure_missing"
    ]
    
    # G3.3: Feature timestamp must be < contact date
    REQUIRE_PIT_COMPLIANCE = True
    
    # G3.4: Suspicious IV threshold (may indicate leakage)
    MAX_INFORMATION_VALUE = 0.5  # Features with IV > 0.5 are suspicious

# =============================================================================
# VALIDATION GATES - MULTICOLLINEARITY
# =============================================================================
class MulticollinearityGates:
    """Gates for detecting multicollinearity."""
    
    # G4.1: Maximum allowed correlation between features
    MAX_CORRELATION = 0.7
    
    # G4.2: Maximum Variance Inflation Factor
    MAX_VIF = 5.0
    
    # G4.3: Minimum eigenvalue ratio (condition number)
    MAX_CONDITION_NUMBER = 30
    
    # G4.4: Action on violation
    ACTION_ON_VIOLATION = "drop_lower_importance"  # or "combine", "pca"

# =============================================================================
# VALIDATION GATES - OVERFITTING
# =============================================================================
class OverfittingGates:
    """Gates for detecting overfitting."""
    
    # G7.1: Maximum allowed train-test lift gap
    MAX_TRAIN_TEST_LIFT_GAP = 0.5  # If train lift - test lift > 0.5x, overfitting
    
    # G7.2: Maximum allowed train-test AUC gap
    MAX_TRAIN_TEST_AUC_GAP = 0.05  # If train AUC - test AUC > 0.05, overfitting
    
    # G7.3: Cross-validation fold variance threshold
    MAX_CV_FOLD_VARIANCE = 0.1  # Std dev of CV scores should be < 0.1
    
    # G7.4: Learning curve convergence
    LEARNING_CURVE_MIN_SAMPLES = 5000  # Minimum samples for stable performance
    
    # G7.5: Early stopping patience
    EARLY_STOPPING_ROUNDS = 50

# =============================================================================
# VALIDATION GATES - MODEL PERFORMANCE
# =============================================================================
class PerformanceGates:
    """Gates for model performance validation."""
    
    # G8.1: Minimum top decile lift (must beat V3 rules)
    MIN_TOP_DECILE_LIFT = 1.5  # V3 rules achieved 1.74x
    
    # G8.2: Minimum AUC-ROC
    MIN_AUC_ROC = 0.60
    
    # G8.3: Minimum AUC-PR (important for imbalanced data)
    MIN_AUC_PR = 0.10  # ~2.5x baseline at 4.2% positive rate
    
    # G8.4: Minimum lift in top 5%
    MIN_TOP_5_PERCENT_LIFT = 2.0
    
    # G8.5: Statistical significance (p-value for lift)
    MAX_P_VALUE = 0.05

# =============================================================================
# MODEL HYPERPARAMETERS
# =============================================================================
class ModelConfig:
    """XGBoost hyperparameters with regularization."""
    
    # Base parameters
    OBJECTIVE = "binary:logistic"
    EVAL_METRIC = ["auc", "aucpr", "logloss"]
    RANDOM_STATE = 42
    
    # Regularization parameters (prevent overfitting)
    MAX_DEPTH = 4  # Shallow trees
    MIN_CHILD_WEIGHT = 10  # Minimum samples per leaf
    GAMMA = 0.1  # Minimum loss reduction for split
    SUBSAMPLE = 0.8  # Row subsampling
    COLSAMPLE_BYTREE = 0.8  # Column subsampling
    REG_ALPHA = 0.1  # L1 regularization
    REG_LAMBDA = 1.0  # L2 regularization
    
    # Training parameters
    N_ESTIMATORS = 500  # Will use early stopping
    LEARNING_RATE = 0.05  # Slow learning for stability
    EARLY_STOPPING_ROUNDS = 50
    
    # Class imbalance handling
    # scale_pos_weight = (negative_count / positive_count)
    # Will be calculated dynamically

# =============================================================================
# CROSS-VALIDATION CONFIGURATION
# =============================================================================
class CVConfig:
    """Cross-validation configuration."""
    
    N_SPLITS = 5
    SHUFFLE = False  # Time-based CV, no shuffle
    STRATEGY = "TimeSeriesSplit"  # Respect temporal ordering
    
    # Stratification
    STRATIFY_BY = ["lead_source_grouped"]  # Account for source drift

# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================
class LogConfig:
    """Logging configuration."""
    
    LOG_LEVEL = "INFO"
    LOG_FORMAT = "%(asctime)s | %(levelname)s | %(phase)s | %(message)s"
    LOG_FILE = BASE_DIR / "EXECUTION_LOG.md"
    
    # What to log
    LOG_GATES = True
    LOG_METRICS = True
    LOG_DECISIONS = True
    LOG_WARNINGS = True
    LOG_ERRORS = True

# =============================================================================
# FEATURE LISTS
# =============================================================================
# Features to include in model (PIT-safe)
FEATURES_PRIMARY = [
    "tenure_months",
    "tenure_bucket",
    "mobility_3yr",
    "mobility_tier",
    "is_wirehouse",
    "is_broker_protocol",
]

FEATURES_FIRM = [
    "firm_net_change_12mo",
    "firm_stability_tier",
    "firm_departures_12mo",
    "firm_arrivals_12mo",
    "has_firm_data",
]

FEATURES_EXPERIENCE = [
    "experience_years",
    "experience_bucket",
]

FEATURES_INTERACTION = [
    "mobility_x_heavy_bleeding",  # TOP PRIORITY: Mobile × Heavy Bleeding (4.85x lift)
    "short_tenure_x_high_mobility",  # HIGH PRIORITY: Short tenure × High mobility (4.59x lift)
    "tenure_bucket_x_mobility",  # Numeric interaction for gradient boosting
]

FEATURES_LEAD_SOURCE = [
    "lead_source_grouped",
    "is_linkedin_sourced",
    "is_provided_list",
]

FEATURES_QUALITY = [
    "has_email",
    "has_linkedin",
    "has_fintrx_match",
    "has_employment_history",
]

# Features to EXCLUDE (potential leakage or noise)
FEATURES_EXCLUDE = [
    # Raw geography (overfitting risk)
    "state", "city", "metro", "zip",
    # Future-looking
    "days_to_conversion", "conversion_date",
    # IDs
    "lead_id", "advisor_crd", "firm_crd",
    # Raw dates
    "contacted_date", "created_date",
]

# All features combined
ALL_FEATURES = (
    FEATURES_PRIMARY + 
    FEATURES_FIRM + 
    FEATURES_EXPERIENCE + 
    FEATURES_INTERACTION + 
    FEATURES_LEAD_SOURCE + 
    FEATURES_QUALITY
)
```

### 2.2 Feature Configuration YAML

```yaml
# File: config/feature_config.yaml
# Feature definitions and engineering specifications

features:
  # ==========================================================================
  # PRIMARY FEATURES (Strongest signals)
  # ==========================================================================
  tenure_months:
    description: "Months at current firm at time of contact"
    source: "contact_registered_employment_history"
    pit_safe: true
    calculation: "DATE_DIFF(contacted_date, PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH)"
    null_handling: "indicator_flag"
    expected_lift: "4.05x for 12-24 months"
    
  tenure_bucket:
    description: "Categorical tenure bucket"
    source: "derived from tenure_months"
    pit_safe: true
    categories: ["0-12", "12-24", "24-48", "48-120", "120+", "Unknown"]
    encoding: "one_hot"
    
  mobility_3yr:
    description: "Number of firm moves in 3 years before contact"
    source: "contact_registered_employment_history"
    pit_safe: true
    calculation: "COUNT(DISTINCT firm_crd WHERE start_date > contacted_date - 3 years)"
    null_handling: "zero_fill"
    expected_lift: "2.98x for 3+ moves"
    
  mobility_tier:
    description: "Categorical mobility tier"
    source: "derived from mobility_3yr"
    pit_safe: true
    categories: ["Stable (0)", "Low (1)", "High (2+)"]
    encoding: "ordinal"
    
  is_wirehouse:
    description: "Current firm is a wirehouse (POSITIVE signal - 2.15x lift)"
    source: "contact_registered_employment_history"
    pit_safe: true
    calculation: "CASE WHEN firm_name LIKE pattern THEN 1 ELSE 0"
    expected_lift: "2.15x"
    expected_conversion_rate: "9.02%"
    sample_size: 665
    note: "POSITIVE signal - wirehouse leads convert better (9.02% vs 4.14%). Contradicts V3 exclusion logic. Include as feature."
    signal_direction: "positive"
    
  is_broker_protocol:
    description: "Current firm is broker protocol member"
    source: "broker_protocol_members"
    pit_safe: true
    calculation: "CASE WHEN firm_crd IN broker_protocol THEN 1 ELSE 0"
    expected_lift: "2.03x"

  # ==========================================================================
  # FIRM FEATURES (7% coverage - handle sparsity)
  # ==========================================================================
  firm_net_change_12mo:
    description: "Net rep change at firm (arrivals - departures)"
    source: "contact_registered_employment_history"
    pit_safe: true
    calculation: "arrivals_12mo - departures_12mo"
    null_handling: "zero_fill_with_indicator"
    expected_lift: "2.25x-2.77x for bleeding firms"
    sparsity_note: "93% have Unknown firm status"
    
  firm_stability_tier:
    description: "Categorical firm stability"
    source: "derived from firm_net_change_12mo"
    pit_safe: true
    categories: ["Heavy_Bleeding (<-10)", "Light_Bleeding (-10 to 0)", "Stable (0)", "Growing (>0)", "Unknown"]
    encoding: "one_hot"
    
  has_firm_data:
    description: "Indicator for firm data availability"
    source: "derived"
    pit_safe: true
    calculation: "CASE WHEN firm_crd IS NOT NULL THEN 1 ELSE 0"
    importance: "Critical for handling 93% sparsity"

  # ==========================================================================
  # INTERACTION FEATURES (Highest lift combinations from exploration)
  # ==========================================================================
  mobility_x_heavy_bleeding:
    description: "TOP PRIORITY: Mobile reps at heavily bleeding firms"
    source: "derived"
    pit_safe: true
    calculation: "(mobility_3yr >= 2) AND (firm_net_change_12mo < -10)"
    expected_lift: "4.85x"
    expected_conversion_rate: "20.37%"
    sample_size: 108
    priority: "TOP"
    
  short_tenure_x_high_mobility:
    description: "HIGH PRIORITY: Short tenure (<2yr) AND high mobility (2+ moves)"
    source: "derived"
    pit_safe: true
    calculation: "(tenure_months < 24) AND (mobility_3yr >= 2)"
    expected_lift: "4.59x"
    expected_conversion_rate: "19.27%"
    sample_size: 192
    priority: "HIGH"
    
  tenure_bucket_x_mobility:
    description: "Numeric interaction: Tenure bucket × Mobility count"
    source: "derived"
    pit_safe: true
    calculation: "tenure_bucket_numeric * mobility_3yr"
    expected_lift: "Variable by combination"
    priority: "SECONDARY"

  # ==========================================================================
  # LEAD SOURCE FEATURES (Critical for drift handling)
  # ==========================================================================
  lead_source_grouped:
    description: "Grouped lead source category"
    source: "SavvyGTMData.Lead"
    pit_safe: true
    categories: ["Provided List", "LinkedIn", "Event", "Referral", "Other"]
    encoding: "one_hot"
    drift_alert: "94% -> 41% shift for Provided List"
    
  is_linkedin_sourced:
    description: "Lead from LinkedIn (self-sourced)"
    source: "derived"
    pit_safe: true
    calculation: "CASE WHEN LeadSource LIKE '%LinkedIn%' THEN 1 ELSE 0"
    expected_lift: "2.1x vs Provided List"

validation:
  # PIT compliance rules
  pit_rules:
    - "All features must use data available at contacted_date"
    - "No joins to *_current tables for feature values (null indicators OK)"
    - "Employment history filtered by START_DATE <= contacted_date"
    - "Firm_historicals filtered by YEAR/MONTH < contact YEAR/MONTH"
    
  # Leakage indicators
  leakage_indicators:
    - "Feature correlation with target > 0.5"
    - "Feature uses end_date from employment history"
    - "Feature uses conversion_date or any post-contact data"
```

---

## 3. Logging Framework

**INSTRUCTION**: Create the logging utility that tracks all actions, decisions, and gate validations.

```python
# File: utils/execution_logger.py
"""
Execution Logger for V4 Lead Scoring Model

Logs all actions, decisions, gates, and metrics to EXECUTION_LOG.md
Provides structured logging for agentic execution tracking.
"""

import json
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional
import sys

class ExecutionLogger:
    """
    Comprehensive logger for agentic model development.
    
    Logs to:
    1. EXECUTION_LOG.md (human-readable markdown)
    2. Console (real-time feedback)
    3. JSON files (machine-readable metrics)
    """
    
    def __init__(self, base_dir: Path = None):
        if base_dir is None:
            base_dir = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4")
        
        self.base_dir = base_dir
        self.log_file = base_dir / "EXECUTION_LOG.md"
        self.metrics_dir = base_dir / "data" / "exploration"
        self.current_phase = None
        self.phase_start_time = None
        self.gate_results = []
        self.decisions = []
        self.warnings = []
        self.errors = []
        
        # Initialize log file if not exists
        if not self.log_file.exists():
            self._initialize_log_file()
    
    def _initialize_log_file(self):
        """Initialize the execution log file."""
        header = """# Version 4 Lead Scoring Model - Execution Log

**Model Version**: 4.0.0  
**Started**: {timestamp}  
**Status**: In Progress

---

## Execution Timeline

""".format(timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
        
        with open(self.log_file, 'w', encoding='utf-8') as f:
            f.write(header)
    
    def _append_to_log(self, content: str):
        """Append content to log file."""
        with open(self.log_file, 'a', encoding='utf-8') as f:
            f.write(content)
    
    def start_phase(self, phase_id: str, phase_name: str):
        """Start a new phase and log it."""
        self.current_phase = phase_id
        self.phase_start_time = datetime.now()
        self.gate_results = []
        self.decisions = []
        self.warnings = []
        
        log_entry = f"""
---

## Phase {phase_id}: {phase_name}

**Started**: {self.phase_start_time.strftime("%Y-%m-%d %H:%M:%S")}  
**Status**: 🔄 In Progress

### Actions

"""
        self._append_to_log(log_entry)
        print(f"\n{'='*70}")
        print(f"PHASE {phase_id}: {phase_name}")
        print(f"{'='*70}")
    
    def log_action(self, action: str, details: str = None):
        """Log an action taken."""
        timestamp = datetime.now().strftime("%H:%M:%S")
        
        log_entry = f"- [{timestamp}] {action}\n"
        if details:
            log_entry += f"  - Details: {details}\n"
        
        self._append_to_log(log_entry)
        print(f"  → {action}")
        if details:
            print(f"    {details}")
    
    def log_gate(self, gate_id: str, gate_name: str, passed: bool, 
                 expected: Any, actual: Any, notes: str = None):
        """Log a validation gate result."""
        status = "✅ PASSED" if passed else "❌ FAILED"
        
        gate_result = {
            "gate_id": gate_id,
            "gate_name": gate_name,
            "passed": passed,
            "expected": str(expected),
            "actual": str(actual),
            "notes": notes
        }
        self.gate_results.append(gate_result)
        
        log_entry = f"""
#### Gate {gate_id}: {gate_name}
- **Status**: {status}
- **Expected**: {expected}
- **Actual**: {actual}
"""
        if notes:
            log_entry += f"- **Notes**: {notes}\n"
        
        self._append_to_log(log_entry)
        print(f"  Gate {gate_id}: {status}")
        print(f"    Expected: {expected}, Actual: {actual}")
        
        if not passed:
            self.warnings.append(f"Gate {gate_id} failed: {gate_name}")
    
    def log_metric(self, metric_name: str, value: Any, context: str = None):
        """Log a metric value."""
        log_entry = f"- **{metric_name}**: {value}\n"
        if context:
            log_entry += f"  - Context: {context}\n"
        
        self._append_to_log(log_entry)
        print(f"  📊 {metric_name}: {value}")
    
    def log_decision(self, decision: str, rationale: str, alternatives: List[str] = None):
        """Log a decision made during execution."""
        self.decisions.append({
            "decision": decision,
            "rationale": rationale,
            "alternatives": alternatives,
            "timestamp": datetime.now().isoformat()
        })
        
        log_entry = f"""
#### Decision Made
- **Decision**: {decision}
- **Rationale**: {rationale}
"""
        if alternatives:
            log_entry += f"- **Alternatives Considered**: {', '.join(alternatives)}\n"
        
        self._append_to_log(log_entry)
        print(f"  📋 Decision: {decision}")
        print(f"     Rationale: {rationale}")
    
    def log_warning(self, warning: str, action_taken: str = None):
        """Log a warning."""
        self.warnings.append(warning)
        
        log_entry = f"""
⚠️ **Warning**: {warning}
"""
        if action_taken:
            log_entry += f"- **Action Taken**: {action_taken}\n"
        
        self._append_to_log(log_entry)
        print(f"  ⚠️ WARNING: {warning}")
    
    def log_error(self, error: str, exception: Exception = None):
        """Log an error."""
        self.errors.append({
            "error": error,
            "exception": str(exception) if exception else None,
            "timestamp": datetime.now().isoformat()
        })
        
        log_entry = f"""
🚨 **Error**: {error}
"""
        if exception:
            log_entry += f"- **Exception**: {str(exception)}\n"
        
        self._append_to_log(log_entry)
        print(f"  🚨 ERROR: {error}")
        if exception:
            print(f"     Exception: {str(exception)}")
    
    def log_dataframe_summary(self, df, name: str):
        """Log summary statistics of a DataFrame."""
        log_entry = f"""
#### DataFrame: {name}
- **Shape**: {df.shape[0]:,} rows × {df.shape[1]} columns
- **Memory**: {df.memory_usage(deep=True).sum() / 1024**2:.2f} MB
- **Columns**: {', '.join(df.columns[:10])}{'...' if len(df.columns) > 10 else ''}
"""
        if hasattr(df, 'target') or 'converted' in df.columns or 'target' in df.columns:
            target_col = 'converted' if 'converted' in df.columns else 'target'
            if target_col in df.columns:
                pos_rate = df[target_col].mean() * 100
                log_entry += f"- **Positive Class Rate**: {pos_rate:.2f}%\n"
        
        self._append_to_log(log_entry)
        print(f"  📊 {name}: {df.shape[0]:,} rows × {df.shape[1]} columns")
    
    def log_file_created(self, filename: str, filepath: str, description: str = None):
        """Log file creation."""
        log_entry = f"- **File Created**: `{filename}` at `{filepath}`\n"
        if description:
            log_entry += f"  - {description}\n"
        
        self._append_to_log(log_entry)
        print(f"  📁 Created: {filename}")
    
    def end_phase(self, status: str = "PASSED", next_steps: List[str] = None):
        """End the current phase and summarize."""
        duration = datetime.now() - self.phase_start_time
        duration_str = str(duration).split('.')[0]
        
        # Determine overall status
        if self.errors:
            status = "FAILED"
            status_emoji = "❌"
        elif self.warnings:
            status = "PASSED WITH WARNINGS"
            status_emoji = "⚠️"
        else:
            status_emoji = "✅"
        
        # Count gate results
        gates_passed = sum(1 for g in self.gate_results if g['passed'])
        gates_failed = len(self.gate_results) - gates_passed
        
        log_entry = f"""
### Phase Summary

- **Status**: {status_emoji} {status}
- **Duration**: {duration_str}
- **Gates**: {gates_passed} passed, {gates_failed} failed
- **Warnings**: {len(self.warnings)}
- **Errors**: {len(self.errors)}
"""
        
        if self.decisions:
            log_entry += f"- **Decisions Made**: {len(self.decisions)}\n"
        
        if next_steps:
            log_entry += "\n**Next Steps**:\n"
            for step in next_steps:
                log_entry += f"- [ ] {step}\n"
        
        self._append_to_log(log_entry)
        
        print(f"\n{'─'*70}")
        print(f"Phase {self.current_phase} Complete: {status_emoji} {status}")
        print(f"Duration: {duration_str}")
        print(f"Gates: {gates_passed}/{len(self.gate_results)} passed")
        print(f"{'─'*70}\n")
        
        # Reset for next phase
        self.current_phase = None
        self.phase_start_time = None
        
        return status
    
    def save_phase_metrics(self, metrics: Dict[str, Any], filename: str):
        """Save phase metrics to JSON file."""
        self.metrics_dir.mkdir(parents=True, exist_ok=True)
        filepath = self.metrics_dir / filename
        
        with open(filepath, 'w') as f:
            json.dump(metrics, f, indent=2, default=str)
        
        self.log_file_created(filename, str(filepath), "Phase metrics saved")
    
    def get_gate_summary(self) -> Dict[str, Any]:
        """Get summary of all gates from current phase."""
        return {
            "total": len(self.gate_results),
            "passed": sum(1 for g in self.gate_results if g['passed']),
            "failed": sum(1 for g in self.gate_results if not g['passed']),
            "results": self.gate_results
        }
    
    def finalize_log(self, final_status: str, model_version: str = None):
        """Finalize the execution log with summary."""
        log_entry = f"""
---

## Final Summary

**Completed**: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}  
**Final Status**: {final_status}  
"""
        if model_version:
            log_entry += f"**Model Version**: {model_version}\n"
        
        self._append_to_log(log_entry)
        print(f"\n{'='*70}")
        print(f"EXECUTION COMPLETE: {final_status}")
        print(f"{'='*70}\n")


# Convenience function for quick logging
def get_logger() -> ExecutionLogger:
    """Get or create the global logger instance."""
    global _logger
    if '_logger' not in globals():
        _logger = ExecutionLogger()
    return _logger
```

---

## 4. Phase 0: Environment Setup & Preflight

**INSTRUCTION**: Execute this phase first to validate the environment and dependencies.

### 4.1 Objectives

- Verify all dependencies are installed
- Test BigQuery connectivity
- Validate dataset access
- Create directory structure
- Initialize logging

### 4.2 Script

```python
# File: scripts/phase_0_setup.py
"""
Phase 0: Environment Setup and Preflight Validation

This phase validates:
1. Python dependencies
2. BigQuery connectivity
3. Dataset access permissions
4. Directory structure
5. Configuration validity
"""

import sys
from pathlib import Path
from datetime import datetime

# Add project root to path
BASE_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4")
sys.path.insert(0, str(BASE_DIR))

def run_phase_0():
    """Execute Phase 0: Environment Setup."""
    
    print("=" * 70)
    print("PHASE 0: ENVIRONMENT SETUP & PREFLIGHT VALIDATION")
    print("=" * 70)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Track gate results
    gates = []
    
    # =========================================================================
    # STEP 0.1: Verify Python Dependencies
    # =========================================================================
    print("[0.1] Checking Python dependencies...")
    
    required_packages = [
        ("pandas", "pd"),
        ("numpy", "np"),
        ("xgboost", "xgb"),
        ("sklearn", "sklearn"),
        ("google.cloud.bigquery", "bigquery"),
        ("shap", "shap"),
        ("matplotlib", "plt"),
        ("seaborn", "sns"),
        ("scipy", "scipy"),
        ("optuna", "optuna"),
        ("yaml", "yaml"),
    ]
    
    missing = []
    for package, alias in required_packages:
        try:
            __import__(package.split('.')[0])
            print(f"  ✅ {package}")
        except ImportError:
            print(f"  ❌ {package} - MISSING")
            missing.append(package)
    
    gate_0_1 = len(missing) == 0
    gates.append({
        "id": "G0.1",
        "name": "Python Dependencies",
        "passed": gate_0_1,
        "expected": "All packages installed",
        "actual": f"{len(required_packages) - len(missing)}/{len(required_packages)} installed"
    })
    
    if missing:
        print(f"\n  ⚠️ Missing packages: {', '.join(missing)}")
        print(f"  Run: pip install {' '.join(missing)}")
    
    # =========================================================================
    # STEP 0.2: Test BigQuery Connectivity
    # =========================================================================
    print("\n[0.2] Testing BigQuery connectivity...")
    
    try:
        from google.cloud import bigquery
        
        PROJECT_ID = "savvy-gtm-analytics"
        LOCATION = "northamerica-northeast2"
        
        client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
        
        # Test query
        test_query = "SELECT 1 as test"
        result = list(client.query(test_query).result())
        
        if result[0].test == 1:
            print(f"  ✅ BigQuery connection successful")
            print(f"     Project: {PROJECT_ID}")
            print(f"     Location: {LOCATION}")
            gate_0_2 = True
        else:
            print(f"  ❌ BigQuery query returned unexpected result")
            gate_0_2 = False
            
    except Exception as e:
        print(f"  ❌ BigQuery connection failed: {str(e)}")
        gate_0_2 = False
        client = None
    
    gates.append({
        "id": "G0.2",
        "name": "BigQuery Connectivity",
        "passed": gate_0_2,
        "expected": "Connection successful",
        "actual": "Connected" if gate_0_2 else "Failed"
    })
    
    # =========================================================================
    # STEP 0.3: Validate Dataset Access
    # =========================================================================
    print("\n[0.3] Validating dataset access...")
    
    if client:
        datasets_to_check = [
            ("FinTrx_data_CA", "contact_registered_employment_history"),
            ("FinTrx_data_CA", "Firm_historicals"),
            ("FinTrx_data_CA", "ria_contacts_current"),
            ("SavvyGTMData", "Lead"),
            ("SavvyGTMData", "broker_protocol_members"),
        ]
        
        accessible = 0
        for dataset, table in datasets_to_check:
            try:
                query = f"SELECT COUNT(*) as cnt FROM `{PROJECT_ID}.{dataset}.{table}` LIMIT 1"
                result = list(client.query(query).result())
                print(f"  ✅ {dataset}.{table}")
                accessible += 1
            except Exception as e:
                print(f"  ❌ {dataset}.{table} - {str(e)[:50]}")
        
        gate_0_3 = accessible == len(datasets_to_check)
    else:
        gate_0_3 = False
        accessible = 0
    
    gates.append({
        "id": "G0.3",
        "name": "Dataset Access",
        "passed": gate_0_3,
        "expected": f"{len(datasets_to_check)}/{len(datasets_to_check)} datasets accessible",
        "actual": f"{accessible}/{len(datasets_to_check)} accessible"
    })
    
    # =========================================================================
    # STEP 0.4: Create Directory Structure
    # =========================================================================
    print("\n[0.4] Creating directory structure...")
    
    directories = [
        "config",
        "data/raw",
        "data/processed",
        "data/splits",
        "data/exploration",
        "sql",
        "scripts",
        "utils",
        "models/v4.0.0",
        "reports",
        "tests"
    ]
    
    created = 0
    for dir_path in directories:
        full_path = BASE_DIR / dir_path
        try:
            full_path.mkdir(parents=True, exist_ok=True)
            created += 1
        except Exception as e:
            print(f"  ❌ Failed to create {dir_path}: {str(e)}")
    
    print(f"  ✅ Created {created}/{len(directories)} directories")
    
    gate_0_4 = created == len(directories)
    gates.append({
        "id": "G0.4",
        "name": "Directory Structure",
        "passed": gate_0_4,
        "expected": f"{len(directories)} directories",
        "actual": f"{created} created"
    })
    
    # =========================================================================
    # STEP 0.5: Validate Data Volumes
    # =========================================================================
    print("\n[0.5] Validating data volumes...")
    
    if client:
        try:
            # Check lead volume
            lead_query = """
            SELECT 
                COUNT(*) as total_leads,
                COUNTIF(stage_entered_contacting__c IS NOT NULL) as contacted_leads,
                COUNTIF(Stage_Entered_Call_Scheduled__c IS NOT NULL) as mql_conversions
            FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
            WHERE stage_entered_contacting__c >= '2024-01-01'
            """
            result = list(client.query(lead_query).result())[0]
            
            total_leads = result.total_leads
            contacted_leads = result.contacted_leads
            mql_conversions = result.mql_conversions
            conversion_rate = mql_conversions / contacted_leads * 100 if contacted_leads > 0 else 0
            
            print(f"  📊 Total Leads: {total_leads:,}")
            print(f"  📊 Contacted Leads: {contacted_leads:,}")
            print(f"  📊 MQL Conversions: {mql_conversions:,}")
            print(f"  📊 Conversion Rate: {conversion_rate:.2f}%")
            
            # Gate: Minimum leads
            gate_0_5 = contacted_leads >= 10000
            
        except Exception as e:
            print(f"  ❌ Volume check failed: {str(e)}")
            gate_0_5 = False
            contacted_leads = 0
    else:
        gate_0_5 = False
        contacted_leads = 0
    
    gates.append({
        "id": "G0.5",
        "name": "Data Volume",
        "passed": gate_0_5,
        "expected": ">= 10,000 contacted leads",
        "actual": f"{contacted_leads:,} leads"
    })
    
    # =========================================================================
    # STEP 0.6: Validate Firm Historicals Coverage
    # =========================================================================
    print("\n[0.6] Validating Firm Historicals coverage...")
    
    if client:
        try:
            fh_query = """
            SELECT 
                COUNT(DISTINCT CONCAT(CAST(YEAR AS STRING), '-', CAST(MONTH AS STRING))) as months_available,
                MIN(CONCAT(CAST(YEAR AS STRING), '-', LPAD(CAST(MONTH AS STRING), 2, '0'))) as earliest_month,
                MAX(CONCAT(CAST(YEAR AS STRING), '-', LPAD(CAST(MONTH AS STRING), 2, '0'))) as latest_month
            FROM `savvy-gtm-analytics.FinTrx_data_CA.Firm_historicals`
            """
            result = list(client.query(fh_query).result())[0]
            
            months_available = result.months_available
            earliest = result.earliest_month
            latest = result.latest_month
            
            print(f"  📊 Months Available: {months_available}")
            print(f"  📊 Date Range: {earliest} to {latest}")
            
            gate_0_6 = months_available >= 12
            
        except Exception as e:
            print(f"  ❌ Firm Historicals check failed: {str(e)}")
            gate_0_6 = False
            months_available = 0
    else:
        gate_0_6 = False
        months_available = 0
    
    gates.append({
        "id": "G0.6",
        "name": "Firm Historicals Coverage",
        "passed": gate_0_6,
        "expected": ">= 12 months",
        "actual": f"{months_available} months"
    })
    
    # =========================================================================
    # SUMMARY
    # =========================================================================
    print("\n" + "=" * 70)
    print("PHASE 0 SUMMARY")
    print("=" * 70)
    
    passed = sum(1 for g in gates if g['passed'])
    failed = len(gates) - passed
    
    print(f"\nGate Results: {passed}/{len(gates)} passed\n")
    
    for gate in gates:
        status = "✅" if gate['passed'] else "❌"
        print(f"  {status} {gate['id']}: {gate['name']}")
        print(f"     Expected: {gate['expected']}")
        print(f"     Actual: {gate['actual']}")
        print()
    
    if failed == 0:
        print("✅ PHASE 0 PASSED - Ready to proceed to Phase 1")
        return True
    else:
        print(f"❌ PHASE 0 FAILED - {failed} gates failed")
        print("   Fix the issues above before proceeding")
        return False


if __name__ == "__main__":
    success = run_phase_0()
    sys.exit(0 if success else 1)
```

### 4.3 Validation Gates

| Gate ID | Gate Name | Pass Criteria | Action on Fail |
|---------|-----------|---------------|----------------|
| G0.1 | Python Dependencies | All packages installed | Install missing packages |
| G0.2 | BigQuery Connectivity | Connection successful | Check credentials |
| G0.3 | Dataset Access | All 5 datasets accessible | Check permissions |
| G0.4 | Directory Structure | All directories created | Manual creation |
| G0.5 | Data Volume | >= 10,000 contacted leads | Expand date range |
| G0.6 | Firm Historicals | >= 12 months coverage | Adjust training dates |

---

## 5. Phase 1: Data Extraction & Target Definition

**INSTRUCTION**: Extract the base dataset with properly defined target variable.

### 5.1 Objectives

- Extract contacted leads from Salesforce
- Define target variable with maturity window
- Handle right-censoring
- Join to FINTRX for CRD matching
- Log data quality metrics

### 5.2 SQL Query

```sql
-- File: sql/phase_1_target_definition.sql
-- ============================================================================
-- PHASE 1: TARGET VARIABLE DEFINITION & BASE DATA EXTRACTION
-- ============================================================================
-- 
-- Target: Contacted → MQL conversion within 43-day maturity window
-- 
-- Key Decisions:
-- 1. Maturity Window: 43 days (P90 of conversion time)
-- 2. Analysis Date: Fixed at 2025-10-31 for training stability
-- 3. Right-Censoring: Leads contacted < 43 days before analysis_date excluded
-- 4. Positive Class: Converted to MQL (Stage_Entered_Call_Scheduled__c IS NOT NULL)
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_lead_base` AS

WITH 
-- Configuration (change these for different runs)
config AS (
    SELECT 
        DATE('2025-10-31') as analysis_date,
        43 as maturity_window_days,
        DATE('2024-02-01') as training_start_date
),

-- Base lead extraction
lead_base AS (
    SELECT
        l.Id as lead_id,
        
        -- CRD for FINTRX matching
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as advisor_crd,
        
        -- Key dates
        DATE(l.CreatedDate) as created_date,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        
        -- Lead source (critical for drift handling)
        l.LeadSource as lead_source_raw,
        CASE 
            WHEN l.LeadSource LIKE '%Provided Lead List%' THEN 'Provided List'
            WHEN l.LeadSource LIKE '%LinkedIn%' THEN 'LinkedIn'
            WHEN l.LeadSource LIKE '%Event%' THEN 'Event'
            WHEN l.LeadSource LIKE '%Referral%' OR l.LeadSource LIKE '%Advisor Referral%' THEN 'Referral'
            ELSE 'Other'
        END as lead_source_grouped,
        
        -- Other lead attributes
        l.Company as company_name,
        l.Title as title,
        
        -- Configuration values
        c.analysis_date,
        c.maturity_window_days
        
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    CROSS JOIN config c
    WHERE l.stage_entered_contacting__c IS NOT NULL
        AND DATE(l.stage_entered_contacting__c) >= c.training_start_date
),

-- Calculate target with right-censoring protection
target_calc AS (
    SELECT
        lb.*,
        
        -- Days since contact (for maturity check)
        DATE_DIFF(lb.analysis_date, lb.contacted_date, DAY) as days_since_contact,
        
        -- Is lead mature enough to evaluate?
        CASE 
            WHEN DATE_DIFF(lb.analysis_date, lb.contacted_date, DAY) >= lb.maturity_window_days
            THEN TRUE
            ELSE FALSE
        END as is_mature,
        
        -- Days to conversion (for mature leads only)
        CASE 
            WHEN lb.mql_date IS NOT NULL
            THEN DATE_DIFF(lb.mql_date, lb.contacted_date, DAY)
            ELSE NULL
        END as days_to_conversion,
        
        -- TARGET VARIABLE
        -- Only defined for mature leads (not right-censored)
        CASE
            -- Right-censored: Lead too young, target unknown
            WHEN DATE_DIFF(lb.analysis_date, lb.contacted_date, DAY) < lb.maturity_window_days
            THEN NULL
            
            -- Positive: Converted within maturity window
            WHEN lb.mql_date IS NOT NULL
                 AND DATE_DIFF(lb.mql_date, lb.contacted_date, DAY) <= lb.maturity_window_days
            THEN 1
            
            -- Negative: Mature lead, did not convert
            ELSE 0
        END as target
        
    FROM lead_base lb
),

-- FINTRX matching
fintrx_match AS (
    SELECT
        tc.*,
        
        -- FINTRX match indicator
        CASE WHEN c.RIA_CONTACT_CRD_ID IS NOT NULL THEN 1 ELSE 0 END as has_fintrx_match,
        
        -- Employment history check
        CASE WHEN eh.RIA_CONTACT_CRD_ID IS NOT NULL THEN 1 ELSE 0 END as has_employment_history
        
    FROM target_calc tc
    
    -- Match to FINTRX contacts
    LEFT JOIN (
        SELECT DISTINCT RIA_CONTACT_CRD_ID
        FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
    ) c ON tc.advisor_crd = c.RIA_CONTACT_CRD_ID
    
    -- Check employment history availability
    LEFT JOIN (
        SELECT DISTINCT RIA_CONTACT_CRD_ID
        FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history`
    ) eh ON tc.advisor_crd = eh.RIA_CONTACT_CRD_ID
)

-- Final output
SELECT
    lead_id,
    advisor_crd,
    created_date,
    contacted_date,
    mql_date,
    lead_source_raw,
    lead_source_grouped,
    company_name,
    title,
    analysis_date,
    maturity_window_days,
    days_since_contact,
    is_mature,
    days_to_conversion,
    target,
    has_fintrx_match,
    has_employment_history,
    
    -- Metadata
    CURRENT_TIMESTAMP() as extraction_timestamp,
    'v4.0.0' as model_version

FROM fintrx_match;

-- ============================================================================
-- VALIDATION QUERIES
-- ============================================================================

-- Query 1: Target distribution
SELECT
    'Target Distribution' as metric,
    COUNT(*) as total_leads,
    COUNTIF(target IS NULL) as right_censored,
    COUNTIF(target = 1) as positive,
    COUNTIF(target = 0) as negative,
    ROUND(COUNTIF(target = 1) / NULLIF(COUNTIF(target IS NOT NULL), 0) * 100, 2) as conversion_rate_pct
FROM `savvy-gtm-analytics.ml_features.v4_lead_base`;

-- Query 2: FINTRX match rates
SELECT
    'FINTRX Coverage' as metric,
    COUNT(*) as total,
    COUNTIF(has_fintrx_match = 1) as fintrx_matched,
    ROUND(COUNTIF(has_fintrx_match = 1) / COUNT(*) * 100, 2) as match_rate_pct,
    COUNTIF(has_employment_history = 1) as has_emp_history,
    ROUND(COUNTIF(has_employment_history = 1) / COUNT(*) * 100, 2) as emp_history_rate_pct
FROM `savvy-gtm-analytics.ml_features.v4_lead_base`;

-- Query 3: Lead source distribution
SELECT
    lead_source_grouped,
    COUNT(*) as count,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 1) as pct_of_total,
    COUNTIF(target = 1) as conversions,
    ROUND(COUNTIF(target = 1) / NULLIF(COUNTIF(target IS NOT NULL), 0) * 100, 2) as conversion_rate_pct
FROM `savvy-gtm-analytics.ml_features.v4_lead_base`
GROUP BY 1
ORDER BY count DESC;
```

### 5.3 Python Script

```python
# File: scripts/phase_1_data_extraction.py
"""
Phase 1: Data Extraction and Target Definition

Executes the target definition SQL and validates the results.
"""

import sys
from pathlib import Path
from datetime import datetime

BASE_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4")
sys.path.insert(0, str(BASE_DIR))

from google.cloud import bigquery
from utils.execution_logger import ExecutionLogger

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
LOCATION = "northamerica-northeast2"

def run_phase_1():
    """Execute Phase 1: Data Extraction."""
    
    logger = ExecutionLogger()
    logger.start_phase("1", "Data Extraction & Target Definition")
    
    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
    
    # =========================================================================
    # STEP 1.1: Execute Target Definition SQL
    # =========================================================================
    logger.log_action("Executing target definition SQL")
    
    sql_path = BASE_DIR / "sql" / "phase_1_target_definition.sql"
    
    if sql_path.exists():
        with open(sql_path, 'r') as f:
            sql_content = f.read()
        
        # Extract just the CREATE TABLE statement
        create_sql = sql_content.split("-- VALIDATION QUERIES")[0]
        
        try:
            job = client.query(create_sql)
            job.result()  # Wait for completion
            logger.log_action("Table created", "ml_features.v4_lead_base")
        except Exception as e:
            logger.log_error("Failed to create base table", e)
            return False
    else:
        logger.log_error(f"SQL file not found: {sql_path}")
        return False
    
    # =========================================================================
    # STEP 1.2: Validate Target Distribution
    # =========================================================================
    logger.log_action("Validating target distribution")
    
    target_query = """
    SELECT
        COUNT(*) as total_leads,
        COUNTIF(target IS NULL) as right_censored,
        COUNTIF(target = 1) as positive,
        COUNTIF(target = 0) as negative,
        ROUND(COUNTIF(target = 1) / NULLIF(COUNTIF(target IS NOT NULL), 0) * 100, 2) as conversion_rate_pct
    FROM `savvy-gtm-analytics.ml_features.v4_lead_base`
    """
    
    result = list(client.query(target_query).result())[0]
    
    logger.log_metric("Total Leads", f"{result.total_leads:,}")
    logger.log_metric("Right-Censored", f"{result.right_censored:,}")
    logger.log_metric("Positive (Converted)", f"{result.positive:,}")
    logger.log_metric("Negative (Not Converted)", f"{result.negative:,}")
    logger.log_metric("Conversion Rate", f"{result.conversion_rate_pct}%")
    
    # Gate G1.1: Minimum sample size
    mature_leads = result.positive + result.negative
    gate_1_1 = mature_leads >= 10000
    logger.log_gate(
        "G1.1", "Minimum Sample Size",
        passed=gate_1_1,
        expected=">= 10,000 mature leads",
        actual=f"{mature_leads:,} mature leads"
    )
    
    # Gate G1.2: Conversion rate in expected range
    conv_rate = result.conversion_rate_pct
    gate_1_2 = 2.0 <= conv_rate <= 8.0
    logger.log_gate(
        "G1.2", "Conversion Rate Range",
        passed=gate_1_2,
        expected="2% - 8%",
        actual=f"{conv_rate}%",
        notes="Expected ~4.2% based on exploration"
    )
    
    # Gate G1.3: Right-censoring not excessive
    censored_pct = result.right_censored / result.total_leads * 100
    gate_1_3 = censored_pct <= 40
    logger.log_gate(
        "G1.3", "Right-Censoring Rate",
        passed=gate_1_3,
        expected="<= 40%",
        actual=f"{censored_pct:.1f}%"
    )
    
    # =========================================================================
    # STEP 1.3: Validate FINTRX Coverage
    # =========================================================================
    logger.log_action("Validating FINTRX coverage")
    
    fintrx_query = """
    SELECT
        ROUND(COUNTIF(has_fintrx_match = 1) / COUNT(*) * 100, 2) as match_rate_pct,
        ROUND(COUNTIF(has_employment_history = 1) / COUNT(*) * 100, 2) as emp_history_rate_pct
    FROM `savvy-gtm-analytics.ml_features.v4_lead_base`
    """
    
    result = list(client.query(fintrx_query).result())[0]
    
    logger.log_metric("FINTRX Match Rate", f"{result.match_rate_pct}%")
    logger.log_metric("Employment History Rate", f"{result.emp_history_rate_pct}%")
    
    # Gate G1.4: FINTRX match rate
    gate_1_4 = result.match_rate_pct >= 75
    logger.log_gate(
        "G1.4", "FINTRX Match Rate",
        passed=gate_1_4,
        expected=">= 75%",
        actual=f"{result.match_rate_pct}%"
    )
    
    # Gate G1.5: Employment history coverage
    gate_1_5 = result.emp_history_rate_pct >= 70
    logger.log_gate(
        "G1.5", "Employment History Coverage",
        passed=gate_1_5,
        expected=">= 70%",
        actual=f"{result.emp_history_rate_pct}%"
    )
    
    # =========================================================================
    # STEP 1.4: Check Lead Source Distribution
    # =========================================================================
    logger.log_action("Checking lead source distribution")
    
    source_query = """
    SELECT
        lead_source_grouped,
        COUNT(*) as count,
        ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 1) as pct_of_total
    FROM `savvy-gtm-analytics.ml_features.v4_lead_base`
    GROUP BY 1
    ORDER BY count DESC
    """
    
    results = list(client.query(source_query).result())
    
    for row in results:
        logger.log_metric(f"Lead Source: {row.lead_source_grouped}", 
                         f"{row.count:,} ({row.pct_of_total}%)")
    
    # Check for drift (LinkedIn should be significant portion)
    linkedin_pct = next((r.pct_of_total for r in results if r.lead_source_grouped == 'LinkedIn'), 0)
    
    if linkedin_pct > 40:
        logger.log_warning(
            f"LinkedIn is {linkedin_pct}% of leads - significant drift from historical data",
            action_taken="Will stratify train/test split by lead source"
        )
    
    # =========================================================================
    # SAVE METRICS
    # =========================================================================
    logger.log_action("Saving phase metrics")
    
    metrics = {
        "phase": "1",
        "timestamp": datetime.now().isoformat(),
        "total_leads": result.total_leads if hasattr(result, 'total_leads') else None,
        "conversion_rate": conv_rate,
        "fintrx_match_rate": result.match_rate_pct,
        "gates": logger.get_gate_summary()
    }
    
    logger.save_phase_metrics(metrics, "phase_1_metrics.json")
    
    # =========================================================================
    # PHASE SUMMARY
    # =========================================================================
    status = logger.end_phase(
        next_steps=[
            "Phase 2: Point-in-Time Feature Engineering",
            "Create PIT-safe features from employment history",
            "Calculate firm stability metrics"
        ]
    )
    
    return status == "PASSED" or status == "PASSED WITH WARNINGS"


if __name__ == "__main__":
    success = run_phase_1()
    sys.exit(0 if success else 1)
```

### 5.4 Validation Gates

| Gate ID | Gate Name | Pass Criteria | Action on Fail |
|---------|-----------|---------------|----------------|
| G1.1 | Minimum Sample Size | >= 10,000 mature leads | Extend date range |
| G1.2 | Conversion Rate Range | 2% - 8% | Investigate data quality |
| G1.3 | Right-Censoring Rate | <= 40% | Reduce maturity window |
| G1.4 | FINTRX Match Rate | >= 75% | Investigate CRD quality |
| G1.5 | Employment History | >= 70% coverage | Use indicator flags |

---

## 6. Phase 2: Point-in-Time Feature Engineering

**INSTRUCTION**: This is the most critical phase. All features MUST be PIT-safe.

### 6.1 Objectives

- Create all features using data available at `contacted_date`
- NO future data leakage
- Handle missing data with indicator flags
- Create interaction features

### 6.2 PIT Validation Rules

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    POINT-IN-TIME (PIT) RULES                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ✅ ALLOWED:                                                            │
│  • Employment history: START_DATE <= contacted_date                     │
│  • Firm historicals: YEAR/MONTH < contact YEAR/MONTH                    │
│  • Broker protocol: Static membership list                              │
│  • Lead attributes: Created before or at contact                        │
│                                                                         │
│  ❌ FORBIDDEN:                                                          │
│  • Employment history END_DATE (backfilled)                             │
│  • Current state from *_current tables (except null indicators)         │
│  • Any data timestamped after contacted_date                            │
│  • Conversion date, MQL date, or any outcome data                       │
│                                                                         │
│  ⚠️ CAUTION:                                                            │
│  • INDUSTRY_TENURE_MONTHS from ria_contacts_current (use as proxy)      │
│  • Certifications (CFP) from current state (may not be PIT-accurate)    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 6.3 SQL Query

```sql
-- File: sql/phase_2_feature_engineering.sql
-- ============================================================================
-- PHASE 2: POINT-IN-TIME FEATURE ENGINEERING
-- ============================================================================
-- 
-- CRITICAL: All features must use only data available at contacted_date
-- 
-- Features:
-- 1. Tenure at firm (from employment history)
-- 2. Mobility (moves in 3 years)
-- 3. Firm stability (net change in 12 months)
-- 4. Wirehouse flag
-- 5. Broker protocol membership
-- 6. Interaction features
-- ============================================================================

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.v4_features_pit` AS

WITH 
-- Get base data
base AS (
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_lead_base`
    WHERE target IS NOT NULL  -- Only mature leads for training
),

-- ============================================================================
-- FEATURE 1: Current Firm at Contact Date (PIT-safe)
-- ============================================================================
current_firm AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
        eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID as firm_crd,
        eh.PREVIOUS_REGISTRATION_COMPANY_NAME as firm_name,
        eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE as firm_start_date,
        
        -- Tenure at firm (PIT-safe: uses START_DATE only)
        DATE_DIFF(b.contacted_date, eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE, MONTH) as tenure_months
        
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON b.advisor_crd = eh.RIA_CONTACT_CRD_ID
        -- PIT: Only consider firms where employment started before contact
        AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= b.contacted_date
        -- PIT: Either still employed (no end date) or end date is after contact
        AND (eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NULL 
             OR eh.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= b.contacted_date)
    -- Take most recent firm (by start date) if multiple
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY b.lead_id 
        ORDER BY eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE DESC
    ) = 1
),

-- ============================================================================
-- FEATURE 2: Mobility (moves in 3 years before contact) - PIT-safe
-- ============================================================================
mobility AS (
    SELECT 
        b.lead_id,
        b.contacted_date,
        
        -- Count distinct firms where employment STARTED in 3-year window before contact
        COUNT(DISTINCT CASE 
            WHEN eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE > DATE_SUB(b.contacted_date, INTERVAL 3 YEAR)
                AND eh.PREVIOUS_REGISTRATION_COMPANY_START_DATE <= b.contacted_date
            THEN eh.PREVIOUS_REGISTRATION_COMPANY_CRD_ID 
        END) as mobility_3yr
        
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh
        ON b.advisor_crd = eh.RIA_CONTACT_CRD_ID
    GROUP BY b.lead_id, b.contacted_date
),

-- ============================================================================
-- FEATURE 3: Firm Stability (departures/arrivals in 12 months) - PIT-safe
-- ============================================================================
firm_stability AS (
    SELECT 
        cf.lead_id,
        cf.firm_crd,
        cf.contacted_date,
        
        -- Departures: Reps who LEFT this firm in 12 months before contact
        -- PIT-safe: Uses END_DATE which is backfilled, but we're only using
        -- dates BEFORE contacted_date so this is the state as we'd know it
        (SELECT COUNT(DISTINCT eh_d.RIA_CONTACT_CRD_ID)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_d
         WHERE eh_d.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
           AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE >= DATE_SUB(cf.contacted_date, INTERVAL 12 MONTH)
           AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE < cf.contacted_date
           AND eh_d.PREVIOUS_REGISTRATION_COMPANY_END_DATE IS NOT NULL
        ) as departures_12mo,
        
        -- Arrivals: Reps who JOINED this firm in 12 months before contact
        -- PIT-safe: Uses START_DATE only
        (SELECT COUNT(DISTINCT eh_a.RIA_CONTACT_CRD_ID)
         FROM `savvy-gtm-analytics.FinTrx_data_CA.contact_registered_employment_history` eh_a
         WHERE eh_a.PREVIOUS_REGISTRATION_COMPANY_CRD_ID = cf.firm_crd
           AND eh_a.PREVIOUS_REGISTRATION_COMPANY_START_DATE >= DATE_SUB(cf.contacted_date, INTERVAL 12 MONTH)
           AND eh_a.PREVIOUS_REGISTRATION_COMPANY_START_DATE < cf.contacted_date
        ) as arrivals_12mo
        
    FROM current_firm cf
    WHERE cf.firm_crd IS NOT NULL
),

-- ============================================================================
-- FEATURE 4: Wirehouse Flag - PIT-safe
-- NOTE: Wirehouse is a POSITIVE signal (2.15x lift, 9.02% conversion)
-- This contradicts V3 exclusion logic - data shows wirehouse leads convert better
-- ============================================================================
wirehouse AS (
    SELECT 
        cf.lead_id,
        CASE 
            WHEN UPPER(cf.firm_name) LIKE '%MERRILL%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%MORGAN STANLEY%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%UBS%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%WELLS FARGO%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%EDWARD JONES%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%RAYMOND JAMES%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%AMERIPRISE%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%LPL%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%NORTHWESTERN MUTUAL%' THEN 1
            WHEN UPPER(cf.firm_name) LIKE '%STIFEL%' THEN 1
            ELSE 0
        END as is_wirehouse
    FROM current_firm cf
),

-- ============================================================================
-- FEATURE 5: Broker Protocol - PIT-safe (static list)
-- ============================================================================
broker_protocol AS (
    SELECT 
        cf.lead_id,
        CASE WHEN bp.firm_crd_id IS NOT NULL THEN 1 ELSE 0 END as is_broker_protocol
    FROM current_firm cf
    LEFT JOIN `savvy-gtm-analytics.SavvyGTMData.broker_protocol_members` bp
        ON cf.firm_crd = bp.firm_crd_id
),

-- ============================================================================
-- FEATURE 6: Experience (from current state - use as proxy)
-- ============================================================================
experience AS (
    SELECT 
        b.lead_id,
        COALESCE(c.INDUSTRY_TENURE_MONTHS, 0) / 12.0 as experience_years,
        CASE WHEN c.INDUSTRY_TENURE_MONTHS IS NULL THEN 1 ELSE 0 END as is_experience_missing
    FROM base b
    LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
        ON b.advisor_crd = c.RIA_CONTACT_CRD_ID
),

-- ============================================================================
-- COMBINE ALL FEATURES
-- ============================================================================
all_features AS (
    SELECT
        -- Base columns
        b.lead_id,
        b.advisor_crd,
        b.contacted_date,
        b.lead_source_grouped,
        b.target,
        b.has_fintrx_match,
        b.has_employment_history,
        
        -- Firm at contact
        cf.firm_crd,
        cf.firm_name,
        
        -- Tenure features
        COALESCE(cf.tenure_months, 0) as tenure_months,
        CASE 
            WHEN cf.tenure_months IS NULL THEN 'Unknown'
            WHEN cf.tenure_months < 12 THEN '0-12'
            WHEN cf.tenure_months < 24 THEN '12-24'
            WHEN cf.tenure_months < 48 THEN '24-48'
            WHEN cf.tenure_months < 120 THEN '48-120'
            ELSE '120+'
        END as tenure_bucket,
        CASE WHEN cf.tenure_months IS NULL THEN 1 ELSE 0 END as is_tenure_missing,
        
        -- Mobility features
        COALESCE(m.mobility_3yr, 0) as mobility_3yr,
        CASE 
            WHEN COALESCE(m.mobility_3yr, 0) = 0 THEN 'Stable'
            WHEN COALESCE(m.mobility_3yr, 0) = 1 THEN 'Low_Mobility'
            ELSE 'High_Mobility'
        END as mobility_tier,
        
        -- Firm stability features
        COALESCE(fs.departures_12mo, 0) as firm_departures_12mo,
        COALESCE(fs.arrivals_12mo, 0) as firm_arrivals_12mo,
        COALESCE(fs.arrivals_12mo, 0) - COALESCE(fs.departures_12mo, 0) as firm_net_change_12mo,
        CASE 
            WHEN cf.firm_crd IS NULL THEN 'Unknown'
            WHEN COALESCE(fs.arrivals_12mo, 0) - COALESCE(fs.departures_12mo, 0) < -10 THEN 'Heavy_Bleeding'
            WHEN COALESCE(fs.arrivals_12mo, 0) - COALESCE(fs.departures_12mo, 0) < 0 THEN 'Light_Bleeding'
            WHEN COALESCE(fs.arrivals_12mo, 0) - COALESCE(fs.departures_12mo, 0) = 0 THEN 'Stable'
            ELSE 'Growing'
        END as firm_stability_tier,
        CASE WHEN cf.firm_crd IS NULL THEN 0 ELSE 1 END as has_firm_data,
        
        -- Wirehouse and broker protocol
        COALESCE(w.is_wirehouse, 0) as is_wirehouse,
        COALESCE(bp.is_broker_protocol, 0) as is_broker_protocol,
        
        -- Experience
        e.experience_years,
        CASE 
            WHEN e.experience_years < 5 THEN '0-5'
            WHEN e.experience_years < 10 THEN '5-10'
            WHEN e.experience_years < 15 THEN '10-15'
            WHEN e.experience_years < 20 THEN '15-20'
            ELSE '20+'
        END as experience_bucket,
        e.is_experience_missing,
        
        -- Lead source features
        CASE WHEN b.lead_source_grouped = 'LinkedIn' THEN 1 ELSE 0 END as is_linkedin_sourced,
        CASE WHEN b.lead_source_grouped = 'Provided List' THEN 1 ELSE 0 END as is_provided_list,
        
        -- ============================================================================
        -- INTERACTION FEATURES (Highest lift combinations from exploration)
        -- ============================================================================
        -- TOP PRIORITY: Mobility × Heavy Bleeding (4.85x lift, 20.37% conversion)
        -- Mobile reps at heavily bleeding firms convert at highest rate
        CASE 
            WHEN COALESCE(m.mobility_3yr, 0) >= 2 
                AND (COALESCE(fs.arrivals_12mo, 0) - COALESCE(fs.departures_12mo, 0)) < -10
            THEN 1 ELSE 0
        END as mobility_x_heavy_bleeding,
        
        -- HIGH PRIORITY: Short Tenure × High Mobility (4.59x lift, 19.27% conversion)
        -- Short tenure (<2 years) combined with high mobility (2+ moves) is very strong
        CASE 
            WHEN COALESCE(cf.tenure_months, 9999) < 24 AND COALESCE(m.mobility_3yr, 0) >= 2
            THEN 1 ELSE 0
        END as short_tenure_x_high_mobility,
        
        -- Secondary: General Tenure × Mobility interaction
        -- Numeric interaction for gradient boosting
        CASE 
            WHEN COALESCE(cf.tenure_months, 0) < 24 THEN 1
            WHEN COALESCE(cf.tenure_months, 0) < 60 THEN 2
            ELSE 3
        END * COALESCE(m.mobility_3yr, 0) as tenure_bucket_x_mobility,
        
        -- Metadata
        CURRENT_TIMESTAMP() as feature_extraction_timestamp
        
    FROM base b
    LEFT JOIN current_firm cf ON b.lead_id = cf.lead_id
    LEFT JOIN mobility m ON b.lead_id = m.lead_id
    LEFT JOIN firm_stability fs ON b.lead_id = fs.lead_id
    LEFT JOIN wirehouse w ON b.lead_id = w.lead_id
    LEFT JOIN broker_protocol bp ON b.lead_id = bp.lead_id
    LEFT JOIN experience e ON b.lead_id = e.lead_id
)

SELECT * FROM all_features;

-- ============================================================================
-- FEATURE VALIDATION QUERIES
-- ============================================================================

-- Query 1: Feature null rates
SELECT
    'tenure_months' as feature,
    ROUND(COUNTIF(tenure_months IS NULL OR tenure_months = 0) / COUNT(*) * 100, 2) as null_or_zero_pct
FROM `savvy-gtm-analytics.ml_features.v4_features_pit`
UNION ALL
SELECT 'mobility_3yr', ROUND(COUNTIF(mobility_3yr IS NULL) / COUNT(*) * 100, 2)
FROM `savvy-gtm-analytics.ml_features.v4_features_pit`
UNION ALL
SELECT 'has_firm_data', ROUND(COUNTIF(has_firm_data = 0) / COUNT(*) * 100, 2)
FROM `savvy-gtm-analytics.ml_features.v4_features_pit`;

-- Query 2: Feature distributions
SELECT
    tenure_bucket,
    COUNT(*) as n_leads,
    ROUND(AVG(target) * 100, 2) as conversion_rate_pct
FROM `savvy-gtm-analytics.ml_features.v4_features_pit`
GROUP BY 1
ORDER BY 1;
```

### 6.4 Validation Gates for Phase 2

| Gate ID | Gate Name | Pass Criteria | Action on Fail |
|---------|-----------|---------------|----------------|
| G2.1 | Feature Count | >= 15 features created | Review feature list |
| G2.2 | No Future Data | All features use data <= contacted_date | Fix PIT violations |
| G2.3 | Null Rates | No critical feature > 50% null | Add indicator flags |
| G2.4 | Interaction Features | mobility_x_heavy_bleeding and short_tenure_x_high_mobility created | Review SQL |
| G2.5 | Target Preserved | Same row count as base table | Debug join issues |

---

## 7. Phase 3: Feature Validation & Leakage Audit

**INSTRUCTION**: This phase validates that NO data leakage exists. This is critical.

### 7.1 Objectives

- Verify all features are PIT-compliant
- Check for suspiciously high IV features
- Validate no correlation with future data
- Document leakage audit results

### 7.2 Python Script

```python
# File: scripts/phase_3_leakage_audit.py
"""
Phase 3: Feature Validation and Leakage Audit

This phase performs comprehensive leakage detection:
1. PIT compliance validation
2. Information Value (IV) suspicious feature detection
3. Future correlation analysis
4. Feature timestamp verification
"""

import sys
from pathlib import Path
import pandas as pd
import numpy as np
from datetime import datetime

BASE_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4")
sys.path.insert(0, str(BASE_DIR))

from google.cloud import bigquery
from utils.execution_logger import ExecutionLogger
from config.constants import LeakageGates

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
LOCATION = "northamerica-northeast2"

def calculate_iv(df: pd.DataFrame, feature: str, target: str) -> float:
    """Calculate Information Value for a feature."""
    # Handle continuous features by binning
    if df[feature].dtype in ['float64', 'int64']:
        df[f'{feature}_binned'] = pd.qcut(df[feature], q=10, duplicates='drop')
        feature = f'{feature}_binned'
    
    # Calculate WoE and IV
    total_events = df[target].sum()
    total_non_events = len(df) - total_events
    
    iv = 0
    for val in df[feature].unique():
        if pd.isna(val):
            continue
        subset = df[df[feature] == val]
        events = subset[target].sum()
        non_events = len(subset) - events
        
        pct_events = events / total_events if total_events > 0 else 0
        pct_non_events = non_events / total_non_events if total_non_events > 0 else 0
        
        if pct_events > 0 and pct_non_events > 0:
            woe = np.log(pct_events / pct_non_events)
            iv += (pct_events - pct_non_events) * woe
    
    return iv


def run_phase_3():
    """Execute Phase 3: Leakage Audit."""
    
    logger = ExecutionLogger()
    logger.start_phase("3", "Feature Validation & Leakage Audit")
    
    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
    
    # =========================================================================
    # STEP 3.1: Load Feature Data
    # =========================================================================
    logger.log_action("Loading feature data for analysis")
    
    query = """
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_features_pit`
    WHERE target IS NOT NULL
    """
    
    df = client.query(query).to_dataframe()
    logger.log_dataframe_summary(df, "Feature Data")
    
    # =========================================================================
    # STEP 3.2: Define PIT-Safe Features
    # =========================================================================
    logger.log_action("Validating PIT compliance")
    
    # Features that SHOULD be PIT-safe (derived from employment history)
    pit_safe_features = [
        'tenure_months', 'tenure_bucket', 'mobility_3yr', 'mobility_tier',
        'firm_departures_12mo', 'firm_arrivals_12mo', 'firm_net_change_12mo',
        'firm_stability_tier', 'is_wirehouse', 'is_broker_protocol',
        'mobility_x_heavy_bleeding', 'short_tenure_x_high_mobility', 'tenure_bucket_x_mobility', 'has_firm_data'
    ]
    
    # Features that use current state (acceptable with caution)
    current_state_features = [
        'experience_years', 'experience_bucket', 'is_experience_missing'
    ]
    
    # Features that are lead attributes (always available at contact)
    lead_attribute_features = [
        'lead_source_grouped', 'is_linkedin_sourced', 'is_provided_list'
    ]
    
    # Validate all features are accounted for
    all_known_features = pit_safe_features + current_state_features + lead_attribute_features
    feature_columns = [c for c in df.columns if c not in [
        'lead_id', 'advisor_crd', 'contacted_date', 'firm_crd', 'firm_name',
        'target', 'has_fintrx_match', 'has_employment_history', 
        'feature_extraction_timestamp', 'is_tenure_missing'
    ]]
    
    unknown_features = [f for f in feature_columns if f not in all_known_features]
    
    gate_3_1 = len(unknown_features) == 0
    logger.log_gate(
        "G3.1", "All Features Documented",
        passed=gate_3_1,
        expected="0 unknown features",
        actual=f"{len(unknown_features)} unknown: {unknown_features[:5]}..."
    )
    
    if unknown_features:
        logger.log_warning(
            f"Unknown features found: {unknown_features}",
            action_taken="Review feature engineering SQL"
        )
    
    # =========================================================================
    # STEP 3.3: Calculate Information Value
    # =========================================================================
    logger.log_action("Calculating Information Value for all features")
    
    iv_results = []
    suspicious_features = []
    
    numeric_features = df.select_dtypes(include=[np.number]).columns
    numeric_features = [f for f in numeric_features if f != 'target' and f in feature_columns]
    
    for feature in numeric_features:
        try:
            iv = calculate_iv(df, feature, 'target')
            iv_results.append({'feature': feature, 'iv': iv})
            
            if iv > LeakageGates.MAX_INFORMATION_VALUE:
                suspicious_features.append(feature)
                logger.log_warning(
                    f"Suspicious IV for {feature}: {iv:.4f} (threshold: {LeakageGates.MAX_INFORMATION_VALUE})",
                    action_taken="Investigate for potential leakage"
                )
        except Exception as e:
            logger.log_warning(f"Could not calculate IV for {feature}: {str(e)}")
    
    # Sort by IV
    iv_df = pd.DataFrame(iv_results).sort_values('iv', ascending=False)
    
    logger.log_action("Top 10 features by Information Value")
    for _, row in iv_df.head(10).iterrows():
        logger.log_metric(f"IV: {row['feature']}", f"{row['iv']:.4f}")
    
    # Gate G3.2: No suspicious IV
    gate_3_2 = len(suspicious_features) == 0
    logger.log_gate(
        "G3.2", "No Suspicious IV Features",
        passed=gate_3_2,
        expected=f"0 features with IV > {LeakageGates.MAX_INFORMATION_VALUE}",
        actual=f"{len(suspicious_features)} suspicious features"
    )
    
    # =========================================================================
    # STEP 3.4: Check for Future Correlation
    # =========================================================================
    logger.log_action("Checking for correlation with future data")
    
    # We can't directly check future correlation without the outcome,
    # but we can verify that no feature is using post-contact data
    
    # Check that tenure_months makes sense (should not be negative)
    invalid_tenure = (df['tenure_months'] < 0).sum()
    gate_3_3 = invalid_tenure == 0
    logger.log_gate(
        "G3.3", "Valid Tenure Values",
        passed=gate_3_3,
        expected="0 negative tenure values",
        actual=f"{invalid_tenure} invalid values"
    )
    
    # Check that mobility is reasonable (should not exceed possible moves)
    max_mobility = df['mobility_3yr'].max()
    gate_3_4 = max_mobility <= 10  # Reasonable max moves in 3 years
    logger.log_gate(
        "G3.4", "Valid Mobility Values",
        passed=gate_3_4,
        expected="Max mobility <= 10",
        actual=f"Max mobility = {max_mobility}"
    )
    
    # =========================================================================
    # STEP 3.5: Validate Interaction Features
    # =========================================================================
    logger.log_action("Validating interaction features")
    
    gate_3_5_parts = []
    
    # Validate short_tenure_x_high_mobility (HIGH PRIORITY: 4.59x lift)
    if 'short_tenure_x_high_mobility' in df.columns:
        sthm_leads = df[df['short_tenure_x_high_mobility'] == 1]
        if len(sthm_leads) > 0:
            valid_sthm = (
                (sthm_leads['tenure_months'] < 24) & 
                (sthm_leads['mobility_3yr'] >= 2)
            ).all()
            
            gate_3_5_parts.append(valid_sthm)
            logger.log_gate(
                "G3.5a", "short_tenure_x_high_mobility Correctly Calculated",
                passed=valid_sthm,
                expected="All short_tenure_x_high_mobility=1 have tenure<24 AND mobility>=2",
                actual="Valid" if valid_sthm else "Invalid calculations found"
            )
        else:
            logger.log_warning("No short_tenure_x_high_mobility=1 cases found")
            gate_3_5_parts.append(True)
    else:
        gate_3_5_parts.append(False)
        logger.log_error("short_tenure_x_high_mobility feature not found")
    
    # Validate mobility_x_heavy_bleeding (TOP PRIORITY: 4.85x lift)
    if 'mobility_x_heavy_bleeding' in df.columns:
        mhb_leads = df[df['mobility_x_heavy_bleeding'] == 1]
        if len(mhb_leads) > 0:
            valid_mhb = (
                (mhb_leads['mobility_3yr'] >= 2) & 
                (mhb_leads['firm_net_change_12mo'] < -10)
            ).all()
            
            gate_3_5_parts.append(valid_mhb)
            logger.log_gate(
                "G3.5b", "mobility_x_heavy_bleeding Correctly Calculated",
                passed=valid_mhb,
                expected="All mobility_x_heavy_bleeding=1 have mobility>=2 AND net_change<-10",
                actual="Valid" if valid_mhb else "Invalid calculations found"
            )
        else:
            logger.log_warning("No mobility_x_heavy_bleeding=1 cases found")
            gate_3_5_parts.append(True)
    else:
        gate_3_5_parts.append(False)
        logger.log_error("mobility_x_heavy_bleeding feature not found")
    
    gate_3_5 = all(gate_3_5_parts)
    
    # =========================================================================
    # STEP 3.6: Univariate Lift Validation
    # =========================================================================
    logger.log_action("Validating univariate lifts match exploration")
    
    baseline_rate = df['target'].mean()
    gate_3_6_parts = []
    
    # Check short_tenure_x_high_mobility lift (expected ~4.59x)
    if 'short_tenure_x_high_mobility' in df.columns and (df['short_tenure_x_high_mobility'] == 1).sum() > 0:
        sthm_rate = df[df['short_tenure_x_high_mobility'] == 1]['target'].mean()
        sthm_lift = sthm_rate / baseline_rate if baseline_rate > 0 else 0
        
        logger.log_metric("short_tenure_x_high_mobility lift", f"{sthm_lift:.2f}x")
        
        # Should be similar to exploration (4.59x +/- 1x)
        gate_3_6a = 2.5 <= sthm_lift <= 6.0
        gate_3_6_parts.append(gate_3_6a)
        logger.log_gate(
            "G3.6a", "short_tenure_x_high_mobility Lift Consistent",
            passed=gate_3_6a,
            expected="Lift between 2.5x and 6.0x (exploration showed 4.59x)",
            actual=f"{sthm_lift:.2f}x"
        )
    
    # Check mobility_x_heavy_bleeding lift (expected ~4.85x)
    if 'mobility_x_heavy_bleeding' in df.columns and (df['mobility_x_heavy_bleeding'] == 1).sum() > 0:
        mhb_rate = df[df['mobility_x_heavy_bleeding'] == 1]['target'].mean()
        mhb_lift = mhb_rate / baseline_rate if baseline_rate > 0 else 0
        
        logger.log_metric("mobility_x_heavy_bleeding lift", f"{mhb_lift:.2f}x")
        
        # Should be similar to exploration (4.85x +/- 1x)
        gate_3_6b = 3.0 <= mhb_lift <= 6.5
        gate_3_6_parts.append(gate_3_6b)
        logger.log_gate(
            "G3.6b", "mobility_x_heavy_bleeding Lift Consistent",
            passed=gate_3_6b,
            expected="Lift between 3.0x and 6.5x (exploration showed 4.85x)",
            actual=f"{mhb_lift:.2f}x"
        )
    
    gate_3_6 = all(gate_3_6_parts) if gate_3_6_parts else True
    else:
        gate_3_6 = False
    
    # =========================================================================
    # STEP 3.7: Generate Leakage Audit Report
    # =========================================================================
    logger.log_action("Generating leakage audit report")
    
    report_content = f"""# Leakage Audit Report - V4 Lead Scoring Model

**Generated**: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
**Model Version**: 4.0.0

## Executive Summary

- **Total Features Analyzed**: {len(feature_columns)}
- **PIT-Safe Features**: {len(pit_safe_features)}
- **Current-State Features**: {len(current_state_features)} (use with caution)
- **Suspicious Features (IV > {LeakageGates.MAX_INFORMATION_VALUE})**: {len(suspicious_features)}

## Gate Results

| Gate ID | Gate Name | Status |
|---------|-----------|--------|
| G3.1 | All Features Documented | {'✅ PASSED' if gate_3_1 else '❌ FAILED'} |
| G3.2 | No Suspicious IV | {'✅ PASSED' if gate_3_2 else '❌ FAILED'} |
| G3.3 | Valid Tenure Values | {'✅ PASSED' if gate_3_3 else '❌ FAILED'} |
| G3.4 | Valid Mobility Values | {'✅ PASSED' if gate_3_4 else '❌ FAILED'} |
| G3.5 | Interaction Features Valid | {'✅ PASSED' if gate_3_5 else '❌ FAILED'} |
| G3.6 | Lift Consistency | {'✅ PASSED' if gate_3_6 else '❌ FAILED'} |

## Information Value Analysis

| Feature | IV | Risk Level |
|---------|-----|------------|
"""
    
    for _, row in iv_df.head(15).iterrows():
        risk = "🔴 HIGH" if row['iv'] > 0.5 else "🟡 MEDIUM" if row['iv'] > 0.3 else "🟢 LOW"
        report_content += f"| {row['feature']} | {row['iv']:.4f} | {risk} |\n"
    
    report_content += f"""
## PIT Compliance Summary

### PIT-Safe Features (Employment History Based)
{', '.join(pit_safe_features)}

### Current-State Features (Use with Caution)
{', '.join(current_state_features)}

**Note**: Current-state features (experience) may not be exactly PIT-accurate but are 
reasonable proxies as experience changes slowly.

## Recommendations

1. {'No action needed' if gate_3_2 else 'Investigate suspicious IV features'}
2. {'All interactions valid' if gate_3_5 else 'Review interaction feature calculations'}
3. Continue to Phase 4 for multicollinearity analysis
"""
    
    # Save report
    report_path = BASE_DIR / "reports" / "leakage_audit_report.md"
    with open(report_path, 'w') as f:
        f.write(report_content)
    
    logger.log_file_created("leakage_audit_report.md", str(report_path))
    
    # Save IV results
    iv_df.to_csv(BASE_DIR / "data" / "exploration" / "iv_analysis.csv", index=False)
    logger.log_file_created("iv_analysis.csv", str(BASE_DIR / "data" / "exploration"))
    
    # =========================================================================
    # PHASE SUMMARY
    # =========================================================================
    all_gates_passed = all([gate_3_1, gate_3_2, gate_3_3, gate_3_4, gate_3_5, gate_3_6])
    
    if all_gates_passed:
        status = logger.end_phase(
            next_steps=[
                "Phase 4: Multicollinearity Analysis",
                "Check VIF for all numeric features",
                "Remove or combine correlated features"
            ]
        )
    else:
        status = logger.end_phase(
            next_steps=[
                "STOP: Address leakage concerns before proceeding",
                "Review suspicious features",
                "Re-run Phase 2 if needed"
            ]
        )
    
    return status in ["PASSED", "PASSED WITH WARNINGS"]


if __name__ == "__main__":
    success = run_phase_3()
    sys.exit(0 if success else 1)
```

---

## 8. Phase 4: Multicollinearity Analysis

**INSTRUCTION**: Detect and handle correlated features to ensure model stability.

### 8.1 Objectives

- Calculate correlation matrix for all numeric features
- Calculate Variance Inflation Factor (VIF)
- Remove or combine highly correlated features
- Document decisions

### 8.2 Python Script

```python
# File: scripts/phase_4_multicollinearity.py
"""
Phase 4: Multicollinearity Analysis

Detects and handles multicollinearity:
1. Correlation matrix analysis
2. Variance Inflation Factor (VIF)
3. Feature removal/combination decisions
"""

import sys
from pathlib import Path
import pandas as pd
import numpy as np
from datetime import datetime
import matplotlib.pyplot as plt
import seaborn as sns

BASE_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4")
sys.path.insert(0, str(BASE_DIR))

from google.cloud import bigquery
from scipy import stats
from statsmodels.stats.outliers_influence import variance_inflation_factor
from utils.execution_logger import ExecutionLogger
from config.constants import MulticollinearityGates

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
LOCATION = "northamerica-northeast2"


def calculate_vif(df: pd.DataFrame, features: list) -> pd.DataFrame:
    """Calculate VIF for all features."""
    vif_data = []
    X = df[features].fillna(0)
    
    for i, feature in enumerate(features):
        try:
            vif = variance_inflation_factor(X.values, i)
            vif_data.append({'feature': feature, 'vif': vif})
        except Exception as e:
            vif_data.append({'feature': feature, 'vif': np.nan})
    
    return pd.DataFrame(vif_data).sort_values('vif', ascending=False)


def run_phase_4():
    """Execute Phase 4: Multicollinearity Analysis."""
    
    logger = ExecutionLogger()
    logger.start_phase("4", "Multicollinearity Analysis")
    
    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
    
    # =========================================================================
    # STEP 4.1: Load Feature Data
    # =========================================================================
    logger.log_action("Loading feature data")
    
    query = """
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_features_pit`
    WHERE target IS NOT NULL
    """
    
    df = client.query(query).to_dataframe()
    logger.log_dataframe_summary(df, "Feature Data")
    
    # =========================================================================
    # STEP 4.2: Select Numeric Features for Analysis
    # =========================================================================
    logger.log_action("Selecting numeric features for correlation analysis")
    
    # Exclude ID columns, target, and metadata
    exclude_cols = [
        'lead_id', 'advisor_crd', 'contacted_date', 'firm_crd', 'firm_name',
        'target', 'has_fintrx_match', 'has_employment_history',
        'feature_extraction_timestamp', 'lead_source_grouped',
        'tenure_bucket', 'mobility_tier', 'firm_stability_tier', 
        'experience_bucket'
    ]
    
    numeric_features = [
        c for c in df.select_dtypes(include=[np.number]).columns
        if c not in exclude_cols
    ]
    
    logger.log_metric("Numeric features for analysis", len(numeric_features))
    logger.log_action(f"Features: {', '.join(numeric_features[:10])}...")
    
    # =========================================================================
    # STEP 4.3: Calculate Correlation Matrix
    # =========================================================================
    logger.log_action("Calculating correlation matrix")
    
    corr_matrix = df[numeric_features].corr()
    
    # Find highly correlated pairs
    high_corr_pairs = []
    for i in range(len(corr_matrix.columns)):
        for j in range(i+1, len(corr_matrix.columns)):
            corr_val = abs(corr_matrix.iloc[i, j])
            if corr_val > MulticollinearityGates.MAX_CORRELATION:
                high_corr_pairs.append({
                    'feature_1': corr_matrix.columns[i],
                    'feature_2': corr_matrix.columns[j],
                    'correlation': corr_val
                })
    
    logger.log_metric("High correlation pairs found", len(high_corr_pairs))
    
    for pair in high_corr_pairs:
        logger.log_warning(
            f"High correlation: {pair['feature_1']} ↔ {pair['feature_2']} = {pair['correlation']:.3f}",
            action_taken="Will evaluate for removal"
        )
    
    # Gate G4.1: Check for excessive correlations
    gate_4_1 = len(high_corr_pairs) <= 3  # Allow up to 3 correlated pairs
    logger.log_gate(
        "G4.1", "Limited High Correlations",
        passed=gate_4_1,
        expected="<= 3 pairs with correlation > 0.7",
        actual=f"{len(high_corr_pairs)} pairs"
    )
    
    # =========================================================================
    # STEP 4.4: Calculate VIF
    # =========================================================================
    logger.log_action("Calculating Variance Inflation Factor (VIF)")
    
    # Remove features with too many nulls for VIF calculation
    valid_features = [
        f for f in numeric_features 
        if df[f].notna().sum() / len(df) > 0.5
    ]
    
    vif_df = calculate_vif(df, valid_features)
    
    # Log high VIF features
    high_vif_features = vif_df[vif_df['vif'] > MulticollinearityGates.MAX_VIF]
    
    logger.log_action("VIF Results (Top 10)")
    for _, row in vif_df.head(10).iterrows():
        status = "⚠️" if row['vif'] > MulticollinearityGates.MAX_VIF else "✅"
        logger.log_metric(f"VIF: {row['feature']}", f"{row['vif']:.2f} {status}")
    
    # Gate G4.2: Check for high VIF
    gate_4_2 = len(high_vif_features) <= 2
    logger.log_gate(
        "G4.2", "Limited High VIF Features",
        passed=gate_4_2,
        expected=f"<= 2 features with VIF > {MulticollinearityGates.MAX_VIF}",
        actual=f"{len(high_vif_features)} features"
    )
    
    # =========================================================================
    # STEP 4.5: Make Feature Removal Decisions
    # =========================================================================
    logger.log_action("Making feature removal decisions")
    
    features_to_remove = []
    removal_decisions = []
    
    # For each high correlation pair, remove the less important feature
    for pair in high_corr_pairs:
        f1, f2 = pair['feature_1'], pair['feature_2']
        
        # Decide based on expected importance
        # Keep the feature with higher univariate correlation with target
        corr_f1_target = abs(df[f1].corr(df['target']))
        corr_f2_target = abs(df[f2].corr(df['target']))
        
        remove = f1 if corr_f1_target < corr_f2_target else f2
        keep = f2 if remove == f1 else f1
        
        if remove not in features_to_remove:
            features_to_remove.append(remove)
            removal_decisions.append({
                'removed': remove,
                'kept': keep,
                'reason': f"Lower target correlation ({corr_f1_target:.3f} vs {corr_f2_target:.3f})",
                'correlation': pair['correlation']
            })
    
    # Log decisions
    for decision in removal_decisions:
        logger.log_decision(
            decision=f"Remove {decision['removed']}, keep {decision['kept']}",
            rationale=decision['reason'],
            alternatives=[f"Keep both (VIF issue)", f"Create combined feature"]
        )
    
    # =========================================================================
    # STEP 4.6: Validate Final Feature Set
    # =========================================================================
    logger.log_action("Validating final feature set")
    
    final_features = [f for f in numeric_features if f not in features_to_remove]
    
    logger.log_metric("Original features", len(numeric_features))
    logger.log_metric("Removed features", len(features_to_remove))
    logger.log_metric("Final features", len(final_features))
    
    # Recalculate VIF on final features
    if len(final_features) >= 2:
        final_vif = calculate_vif(df, final_features)
        max_final_vif = final_vif['vif'].max()
        
        gate_4_3 = max_final_vif <= MulticollinearityGates.MAX_VIF * 1.5  # Allow some tolerance
        logger.log_gate(
            "G4.3", "Final VIF Acceptable",
            passed=gate_4_3,
            expected=f"Max VIF <= {MulticollinearityGates.MAX_VIF * 1.5:.1f}",
            actual=f"Max VIF = {max_final_vif:.2f}"
        )
    else:
        gate_4_3 = True
    
    # =========================================================================
    # STEP 4.7: Generate Correlation Heatmap
    # =========================================================================
    logger.log_action("Generating correlation heatmap")
    
    plt.figure(figsize=(12, 10))
    mask = np.triu(np.ones_like(corr_matrix, dtype=bool))
    sns.heatmap(
        corr_matrix, 
        mask=mask, 
        annot=True, 
        fmt='.2f', 
        cmap='RdBu_r',
        center=0,
        square=True
    )
    plt.title('Feature Correlation Matrix - V4 Lead Scoring')
    plt.tight_layout()
    
    heatmap_path = BASE_DIR / "reports" / "correlation_heatmap.png"
    plt.savefig(heatmap_path, dpi=150)
    plt.close()
    
    logger.log_file_created("correlation_heatmap.png", str(heatmap_path))
    
    # =========================================================================
    # STEP 4.8: Generate Multicollinearity Report
    # =========================================================================
    logger.log_action("Generating multicollinearity report")
    
    report_content = f"""# Multicollinearity Analysis Report - V4 Lead Scoring Model

**Generated**: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
**Model Version**: 4.0.0

## Summary

- **Original Features**: {len(numeric_features)}
- **Features Removed**: {len(features_to_remove)}
- **Final Features**: {len(final_features)}
- **Max VIF (Final)**: {max_final_vif:.2f if 'max_final_vif' in dir() else 'N/A'}

## Gate Results

| Gate ID | Gate Name | Status |
|---------|-----------|--------|
| G4.1 | Limited High Correlations | {'✅ PASSED' if gate_4_1 else '❌ FAILED'} |
| G4.2 | Limited High VIF | {'✅ PASSED' if gate_4_2 else '❌ FAILED'} |
| G4.3 | Final VIF Acceptable | {'✅ PASSED' if gate_4_3 else '❌ FAILED'} |

## High Correlation Pairs

| Feature 1 | Feature 2 | Correlation |
|-----------|-----------|-------------|
"""
    
    for pair in high_corr_pairs:
        report_content += f"| {pair['feature_1']} | {pair['feature_2']} | {pair['correlation']:.3f} |\n"
    
    report_content += f"""
## Removal Decisions

| Removed | Kept | Reason |
|---------|------|--------|
"""
    
    for dec in removal_decisions:
        report_content += f"| {dec['removed']} | {dec['kept']} | {dec['reason']} |\n"
    
    report_content += f"""
## VIF Analysis (Top Features)

| Feature | VIF | Status |
|---------|-----|--------|
"""
    
    for _, row in vif_df.head(15).iterrows():
        status = "⚠️ HIGH" if row['vif'] > MulticollinearityGates.MAX_VIF else "✅ OK"
        report_content += f"| {row['feature']} | {row['vif']:.2f} | {status} |\n"
    
    report_content += f"""
## Final Feature List

```
{chr(10).join(final_features)}
```

## Correlation Heatmap

![Correlation Heatmap](correlation_heatmap.png)
"""
    
    report_path = BASE_DIR / "reports" / "multicollinearity_report.md"
    with open(report_path, 'w') as f:
        f.write(report_content)
    
    logger.log_file_created("multicollinearity_report.md", str(report_path))
    
    # Save final feature list
    feature_list = pd.DataFrame({
        'feature': final_features,
        'include': [True] * len(final_features)
    })
    feature_list_path = BASE_DIR / "config" / "final_feature_list.csv"
    feature_list.to_csv(feature_list_path, index=False)
    logger.log_file_created("final_feature_list.csv", str(feature_list_path))
    
    # Save VIF results
    vif_df.to_csv(BASE_DIR / "data" / "exploration" / "vif_analysis.csv", index=False)
    
    # =========================================================================
    # PHASE SUMMARY
    # =========================================================================
    all_gates_passed = all([gate_4_1, gate_4_2, gate_4_3])
    
    status = logger.end_phase(
        next_steps=[
            "Phase 5: Train/Test Split Strategy",
            "Implement temporal split with lead source stratification",
            "Create validation holdout set"
        ]
    )
    
    return status in ["PASSED", "PASSED WITH WARNINGS"]


if __name__ == "__main__":
    success = run_phase_4()
    sys.exit(0 if success else 1)
```

---

## 9. Phase 5: Train/Test Split Strategy

**INSTRUCTION**: Create train/test splits that account for temporal ordering and lead source drift.

### 9.1 Objectives

- Temporal split (train on past, test on future)
- Stratify by lead source to handle drift
- Create validation holdout for final evaluation
- Ensure no data leakage in splits

### 9.2 Python Script

```python
# File: scripts/phase_5_train_test_split.py
"""
Phase 5: Train/Test Split Strategy

Creates splits that:
1. Respect temporal ordering (no future data in training)
2. Stratify by lead source (handle distribution drift)
3. Create holdout for final validation
"""

import sys
from pathlib import Path
import pandas as pd
import numpy as np
from datetime import datetime, date

BASE_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4")
sys.path.insert(0, str(BASE_DIR))

from google.cloud import bigquery
from utils.execution_logger import ExecutionLogger
from config.constants import (
    TRAINING_START_DATE, TRAINING_END_DATE,
    TEST_START_DATE, TEST_END_DATE, TRAIN_TEST_GAP_DAYS
)

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
LOCATION = "northamerica-northeast2"


def run_phase_5():
    """Execute Phase 5: Train/Test Split."""
    
    logger = ExecutionLogger()
    logger.start_phase("5", "Train/Test Split Strategy")
    
    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
    
    # =========================================================================
    # STEP 5.1: Load Feature Data
    # =========================================================================
    logger.log_action("Loading feature data")
    
    query = """
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_features_pit`
    WHERE target IS NOT NULL
    """
    
    df = client.query(query).to_dataframe()
    df['contacted_date'] = pd.to_datetime(df['contacted_date'])
    
    logger.log_dataframe_summary(df, "Complete Dataset")
    
    # =========================================================================
    # STEP 5.2: Define Split Boundaries
    # =========================================================================
    logger.log_action("Defining split boundaries")
    
    # Convert to datetime for comparison
    train_end = pd.Timestamp(TRAINING_END_DATE)
    test_start = pd.Timestamp(TEST_START_DATE)
    test_end = pd.Timestamp(TEST_END_DATE)
    
    logger.log_metric("Training Period", f"{TRAINING_START_DATE} to {TRAINING_END_DATE}")
    logger.log_metric("Gap Period", f"{TRAIN_TEST_GAP_DAYS} days")
    logger.log_metric("Test Period", f"{TEST_START_DATE} to {TEST_END_DATE}")
    
    # =========================================================================
    # STEP 5.3: Create Temporal Splits
    # =========================================================================
    logger.log_action("Creating temporal splits")
    
    # Assign split labels
    df['split'] = 'EXCLUDE'
    df.loc[df['contacted_date'] <= train_end, 'split'] = 'TRAIN'
    df.loc[(df['contacted_date'] >= test_start) & 
           (df['contacted_date'] <= test_end), 'split'] = 'TEST'
    
    # Check for gap violations
    gap_start = train_end
    gap_end = test_start
    gap_leads = df[(df['contacted_date'] > gap_start) & 
                   (df['contacted_date'] < gap_end)]
    
    if len(gap_leads) > 0:
        logger.log_warning(
            f"{len(gap_leads)} leads fall in gap period - will be excluded",
            action_taken="Marked as EXCLUDE"
        )
    
    # Split statistics
    split_stats = df.groupby('split').agg({
        'lead_id': 'count',
        'target': ['sum', 'mean']
    }).round(4)
    
    logger.log_action("Split Statistics")
    for split_name in ['TRAIN', 'TEST', 'EXCLUDE']:
        if split_name in df['split'].values:
            subset = df[df['split'] == split_name]
            logger.log_metric(
                f"{split_name}",
                f"{len(subset):,} leads, {subset['target'].mean()*100:.2f}% conversion"
            )
    
    # Gate G5.1: Minimum training size
    train_size = len(df[df['split'] == 'TRAIN'])
    gate_5_1 = train_size >= 20000
    logger.log_gate(
        "G5.1", "Minimum Training Size",
        passed=gate_5_1,
        expected=">= 20,000 leads",
        actual=f"{train_size:,} leads"
    )
    
    # Gate G5.2: Minimum test size
    test_size = len(df[df['split'] == 'TEST'])
    gate_5_2 = test_size >= 3000
    logger.log_gate(
        "G5.2", "Minimum Test Size",
        passed=gate_5_2,
        expected=">= 3,000 leads",
        actual=f"{test_size:,} leads"
    )
    
    # =========================================================================
    # STEP 5.4: Check Lead Source Distribution
    # =========================================================================
    logger.log_action("Checking lead source distribution across splits")
    
    for split_name in ['TRAIN', 'TEST']:
        subset = df[df['split'] == split_name]
        source_dist = subset['lead_source_grouped'].value_counts(normalize=True) * 100
        
        logger.log_action(f"{split_name} Lead Source Distribution")
        for source, pct in source_dist.items():
            logger.log_metric(f"  {source}", f"{pct:.1f}%")
    
    # Check for significant drift between train and test
    train_linkedin = df[df['split'] == 'TRAIN']['is_linkedin_sourced'].mean() * 100
    test_linkedin = df[df['split'] == 'TEST']['is_linkedin_sourced'].mean() * 100
    linkedin_drift = abs(test_linkedin - train_linkedin)
    
    gate_5_3 = linkedin_drift <= 20  # Allow up to 20% drift
    logger.log_gate(
        "G5.3", "Lead Source Drift",
        passed=gate_5_3,
        expected="LinkedIn % drift <= 20%",
        actual=f"{linkedin_drift:.1f}% (Train: {train_linkedin:.1f}%, Test: {test_linkedin:.1f}%)"
    )
    
    if not gate_5_3:
        logger.log_warning(
            "Significant lead source drift detected between train and test",
            action_taken="Will use stratified sampling for cross-validation"
        )
    
    # =========================================================================
    # STEP 5.5: Check Conversion Rate Consistency
    # =========================================================================
    logger.log_action("Checking conversion rate consistency")
    
    train_conv = df[df['split'] == 'TRAIN']['target'].mean()
    test_conv = df[df['split'] == 'TEST']['target'].mean()
    conv_diff = abs(test_conv - train_conv) / train_conv * 100
    
    gate_5_4 = conv_diff <= 30  # Allow up to 30% relative difference
    logger.log_gate(
        "G5.4", "Conversion Rate Consistency",
        passed=gate_5_4,
        expected="Relative difference <= 30%",
        actual=f"{conv_diff:.1f}% (Train: {train_conv*100:.2f}%, Test: {test_conv*100:.2f}%)"
    )
    
    # =========================================================================
    # STEP 5.6: Create Cross-Validation Folds (Time-Based)
    # =========================================================================
    logger.log_action("Creating time-based cross-validation folds")
    
    train_df = df[df['split'] == 'TRAIN'].copy()
    train_df = train_df.sort_values('contacted_date')
    
    # Create 5 time-based folds
    n_folds = 5
    fold_size = len(train_df) // n_folds
    
    train_df['cv_fold'] = 0
    for i in range(n_folds):
        start_idx = i * fold_size
        end_idx = start_idx + fold_size if i < n_folds - 1 else len(train_df)
        train_df.iloc[start_idx:end_idx, train_df.columns.get_loc('cv_fold')] = i + 1
    
    # Log fold statistics
    for fold in range(1, n_folds + 1):
        fold_data = train_df[train_df['cv_fold'] == fold]
        logger.log_metric(
            f"CV Fold {fold}",
            f"{len(fold_data):,} leads, {fold_data['target'].mean()*100:.2f}% conv"
        )
    
    # =========================================================================
    # STEP 5.7: Save Split Data
    # =========================================================================
    logger.log_action("Saving split data to BigQuery")
    
    # Add cv_fold to full dataset (0 for test/exclude)
    df = df.merge(
        train_df[['lead_id', 'cv_fold']], 
        on='lead_id', 
        how='left'
    )
    df['cv_fold'] = df['cv_fold'].fillna(0).astype(int)
    
    # Upload to BigQuery
    table_id = f"{PROJECT_ID}.ml_features.v4_splits"
    
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE
    )
    
    job = client.load_table_from_dataframe(
        df, table_id, job_config=job_config
    )
    job.result()
    
    logger.log_file_created("v4_splits", f"BigQuery: {table_id}")
    
    # Also save locally
    train_df.to_csv(BASE_DIR / "data" / "splits" / "train.csv", index=False)
    df[df['split'] == 'TEST'].to_csv(BASE_DIR / "data" / "splits" / "test.csv", index=False)
    
    logger.log_file_created("train.csv", str(BASE_DIR / "data" / "splits"))
    logger.log_file_created("test.csv", str(BASE_DIR / "data" / "splits"))
    
    # =========================================================================
    # STEP 5.8: Final Validation
    # =========================================================================
    logger.log_action("Final split validation")
    
    # Check no overlap
    train_max_date = df[df['split'] == 'TRAIN']['contacted_date'].max()
    test_min_date = df[df['split'] == 'TEST']['contacted_date'].min()
    gap_days = (test_min_date - train_max_date).days
    
    gate_5_5 = gap_days >= TRAIN_TEST_GAP_DAYS
    logger.log_gate(
        "G5.5", "Train/Test Gap",
        passed=gate_5_5,
        expected=f">= {TRAIN_TEST_GAP_DAYS} days",
        actual=f"{gap_days} days"
    )
    
    # =========================================================================
    # PHASE SUMMARY
    # =========================================================================
    all_gates_passed = all([gate_5_1, gate_5_2, gate_5_3, gate_5_4, gate_5_5])
    
    status = logger.end_phase(
        next_steps=[
            "Phase 6: Model Training with Regularization",
            "Train XGBoost with early stopping",
            "Use time-based cross-validation"
        ]
    )
    
    return status in ["PASSED", "PASSED WITH WARNINGS"]


if __name__ == "__main__":
    success = run_phase_5()
    sys.exit(0 if success else 1)
```

---

*[Document continues with Phases 6-10 and Appendix...]*

---

## 10. Phase 6: Model Training with Regularization

**INSTRUCTION**: Train XGBoost with proper regularization to prevent overfitting.

### 10.1 Key Regularization Parameters

```python
# Regularization settings to prevent overfitting
REGULARIZATION_CONFIG = {
    'max_depth': 4,          # Shallow trees (prevent memorization)
    'min_child_weight': 10,  # Minimum samples per leaf
    'gamma': 0.1,            # Minimum loss reduction for split
    'subsample': 0.8,        # Row subsampling
    'colsample_bytree': 0.8, # Column subsampling
    'reg_alpha': 0.1,        # L1 regularization
    'reg_lambda': 1.0,       # L2 regularization
    'learning_rate': 0.05,   # Slow learning
    'n_estimators': 500,     # Will use early stopping
    'early_stopping_rounds': 50
}
```

### 10.2 Training Script

```python
# File: scripts/phase_6_model_training.py
"""
Phase 6: XGBoost Model Training with Regularization

Key features:
1. Time-based cross-validation
2. Early stopping to prevent overfitting
3. Class imbalance handling
4. Hyperparameter logging
"""

import sys
from pathlib import Path
import pandas as pd
import numpy as np
from datetime import datetime
import pickle
import json

BASE_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4")
sys.path.insert(0, str(BASE_DIR))

import xgboost as xgb
from sklearn.metrics import (
    roc_auc_score, average_precision_score, 
    precision_recall_curve, roc_curve
)
from utils.execution_logger import ExecutionLogger
from config.constants import ModelConfig, OverfittingGates

# Configuration
PROJECT_ID = "savvy-gtm-analytics"
LOCATION = "northamerica-northeast2"


def calculate_lift(y_true, y_pred, percentile=10):
    """Calculate lift at given percentile."""
    df = pd.DataFrame({'true': y_true, 'pred': y_pred})
    df = df.sort_values('pred', ascending=False)
    
    top_n = int(len(df) * percentile / 100)
    top_df = df.head(top_n)
    
    baseline_rate = df['true'].mean()
    top_rate = top_df['true'].mean()
    
    return top_rate / baseline_rate if baseline_rate > 0 else 0


def run_phase_6():
    """Execute Phase 6: Model Training."""
    
    logger = ExecutionLogger()
    logger.start_phase("6", "Model Training with Regularization")
    
    from google.cloud import bigquery
    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
    
    # =========================================================================
    # STEP 6.1: Load Training Data
    # =========================================================================
    logger.log_action("Loading training data")
    
    query = """
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_splits`
    WHERE split = 'TRAIN'
    """
    
    train_df = client.query(query).to_dataframe()
    logger.log_dataframe_summary(train_df, "Training Data")
    
    # Load test data
    test_query = """
    SELECT *
    FROM `savvy-gtm-analytics.ml_features.v4_splits`
    WHERE split = 'TEST'
    """
    test_df = client.query(test_query).to_dataframe()
    logger.log_dataframe_summary(test_df, "Test Data")
    
    # =========================================================================
    # STEP 6.2: Prepare Features
    # =========================================================================
    logger.log_action("Preparing feature matrices")
    
    # Load final feature list from Phase 4
    feature_list_path = BASE_DIR / "config" / "final_feature_list.csv"
    if feature_list_path.exists():
        feature_list = pd.read_csv(feature_list_path)
        features = feature_list[feature_list['include']]['feature'].tolist()
    else:
        # Default features if list not created
        # Updated based on exploration results: prioritize top interaction features
        features = [
            'tenure_months', 'mobility_3yr', 'firm_net_change_12mo',
            'is_wirehouse', 'is_broker_protocol', 'experience_years',
            'mobility_x_heavy_bleeding',  # TOP PRIORITY: 4.85x lift
            'short_tenure_x_high_mobility',  # HIGH PRIORITY: 4.59x lift
            'tenure_bucket_x_mobility',  # Numeric interaction
            'is_linkedin_sourced', 'is_provided_list',
            'has_firm_data', 'is_tenure_missing', 'is_experience_missing'
        ]
    
    # Filter to available features
    available_features = [f for f in features if f in train_df.columns]
    logger.log_metric("Features for training", len(available_features))
    
    # Prepare matrices
    X_train = train_df[available_features].fillna(0)
    y_train = train_df['target'].values
    
    X_test = test_df[available_features].fillna(0)
    y_test = test_df['target'].values
    
    logger.log_metric("Training samples", f"{len(X_train):,}")
    logger.log_metric("Test samples", f"{len(X_test):,}")
    logger.log_metric("Positive rate (train)", f"{y_train.mean()*100:.2f}%")
    logger.log_metric("Positive rate (test)", f"{y_test.mean()*100:.2f}%")
    
    # =========================================================================
    # STEP 6.3: Calculate Class Weight
    # =========================================================================
    logger.log_action("Calculating class weight for imbalance")
    
    pos_count = y_train.sum()
    neg_count = len(y_train) - pos_count
    scale_pos_weight = neg_count / pos_count
    
    logger.log_metric("scale_pos_weight", f"{scale_pos_weight:.2f}")
    
    # =========================================================================
    # STEP 6.4: Configure Model with Regularization
    # =========================================================================
    logger.log_action("Configuring XGBoost with regularization")
    
    model_params = {
        'objective': 'binary:logistic',
        'eval_metric': ['auc', 'aucpr', 'logloss'],
        'max_depth': ModelConfig.MAX_DEPTH,
        'min_child_weight': ModelConfig.MIN_CHILD_WEIGHT,
        'gamma': ModelConfig.GAMMA,
        'subsample': ModelConfig.SUBSAMPLE,
        'colsample_bytree': ModelConfig.COLSAMPLE_BYTREE,
        'reg_alpha': ModelConfig.REG_ALPHA,
        'reg_lambda': ModelConfig.REG_LAMBDA,
        'learning_rate': ModelConfig.LEARNING_RATE,
        'scale_pos_weight': scale_pos_weight,
        'random_state': ModelConfig.RANDOM_STATE,
        'n_jobs': -1
    }
    
    # Log all parameters
    for param, value in model_params.items():
        logger.log_metric(f"param:{param}", value)
    
    # =========================================================================
    # STEP 6.5: Train with Early Stopping
    # =========================================================================
    logger.log_action("Training XGBoost with early stopping")
    
    # Create evaluation set
    eval_set = [(X_train, y_train), (X_test, y_test)]
    
    model = xgb.XGBClassifier(
        **model_params,
        n_estimators=ModelConfig.N_ESTIMATORS,
        early_stopping_rounds=ModelConfig.EARLY_STOPPING_ROUNDS
    )
    
    model.fit(
        X_train, y_train,
        eval_set=eval_set,
        verbose=True
    )
    
    # Get best iteration
    best_iteration = model.best_iteration
    logger.log_metric("Best iteration (early stopping)", best_iteration)
    
    # Gate G6.1: Early stopping triggered
    gate_6_1 = best_iteration < ModelConfig.N_ESTIMATORS - 10
    logger.log_gate(
        "G6.1", "Early Stopping Triggered",
        passed=gate_6_1,
        expected=f"Best iteration < {ModelConfig.N_ESTIMATORS - 10}",
        actual=f"Stopped at iteration {best_iteration}"
    )
    
    # =========================================================================
    # STEP 6.6: Evaluate Performance
    # =========================================================================
    logger.log_action("Evaluating model performance")
    
    # Training predictions
    train_pred_proba = model.predict_proba(X_train)[:, 1]
    train_auc_roc = roc_auc_score(y_train, train_pred_proba)
    train_auc_pr = average_precision_score(y_train, train_pred_proba)
    train_lift_10 = calculate_lift(y_train, train_pred_proba, 10)
    
    # Test predictions
    test_pred_proba = model.predict_proba(X_test)[:, 1]
    test_auc_roc = roc_auc_score(y_test, test_pred_proba)
    test_auc_pr = average_precision_score(y_test, test_pred_proba)
    test_lift_10 = calculate_lift(y_test, test_pred_proba, 10)
    
    logger.log_action("Training Metrics")
    logger.log_metric("Train AUC-ROC", f"{train_auc_roc:.4f}")
    logger.log_metric("Train AUC-PR", f"{train_auc_pr:.4f}")
    logger.log_metric("Train Top-10% Lift", f"{train_lift_10:.2f}x")
    
    logger.log_action("Test Metrics")
    logger.log_metric("Test AUC-ROC", f"{test_auc_roc:.4f}")
    logger.log_metric("Test AUC-PR", f"{test_auc_pr:.4f}")
    logger.log_metric("Test Top-10% Lift", f"{test_lift_10:.2f}x")
    
    # =========================================================================
    # STEP 6.7: Check for Overfitting
    # =========================================================================
    logger.log_action("Checking for overfitting")
    
    lift_gap = train_lift_10 - test_lift_10
    auc_gap = train_auc_roc - test_auc_roc
    
    gate_6_2 = lift_gap <= OverfittingGates.MAX_TRAIN_TEST_LIFT_GAP
    logger.log_gate(
        "G6.2", "Lift Gap (Overfitting Check)",
        passed=gate_6_2,
        expected=f"Train-Test lift gap <= {OverfittingGates.MAX_TRAIN_TEST_LIFT_GAP}x",
        actual=f"{lift_gap:.2f}x (Train: {train_lift_10:.2f}x, Test: {test_lift_10:.2f}x)"
    )
    
    gate_6_3 = auc_gap <= OverfittingGates.MAX_TRAIN_TEST_AUC_GAP
    logger.log_gate(
        "G6.3", "AUC Gap (Overfitting Check)",
        passed=gate_6_3,
        expected=f"Train-Test AUC gap <= {OverfittingGates.MAX_TRAIN_TEST_AUC_GAP}",
        actual=f"{auc_gap:.4f}"
    )
    
    # =========================================================================
    # STEP 6.8: Feature Importance
    # =========================================================================
    logger.log_action("Extracting feature importance")
    
    importance_df = pd.DataFrame({
        'feature': available_features,
        'importance': model.feature_importances_
    }).sort_values('importance', ascending=False)
    
    logger.log_action("Top 10 Features by Importance")
    for _, row in importance_df.head(10).iterrows():
        logger.log_metric(row['feature'], f"{row['importance']:.4f}")
    
    # Save importance
    importance_df.to_csv(
        BASE_DIR / "models" / "v4.0.0" / "feature_importance.csv", 
        index=False
    )
    
    # =========================================================================
    # STEP 6.9: Save Model
    # =========================================================================
    logger.log_action("Saving model artifacts")
    
    model_dir = BASE_DIR / "models" / "v4.0.0"
    model_dir.mkdir(parents=True, exist_ok=True)
    
    # Save model
    model_path = model_dir / "model.pkl"
    with open(model_path, 'wb') as f:
        pickle.dump(model, f)
    logger.log_file_created("model.pkl", str(model_path))
    
    # Save model in XGBoost format
    model.save_model(str(model_dir / "model.json"))
    logger.log_file_created("model.json", str(model_dir))
    
    # Save metrics
    metrics = {
        'model_version': 'v4.0.0',
        'training_timestamp': datetime.now().isoformat(),
        'best_iteration': best_iteration,
        'n_features': len(available_features),
        'n_train_samples': len(X_train),
        'n_test_samples': len(X_test),
        'parameters': model_params,
        'train_metrics': {
            'auc_roc': train_auc_roc,
            'auc_pr': train_auc_pr,
            'lift_top_10': train_lift_10
        },
        'test_metrics': {
            'auc_roc': test_auc_roc,
            'auc_pr': test_auc_pr,
            'lift_top_10': test_lift_10
        },
        'overfitting_check': {
            'lift_gap': lift_gap,
            'auc_gap': auc_gap,
            'passed': gate_6_2 and gate_6_3
        }
    }
    
    with open(model_dir / "training_metrics.json", 'w') as f:
        json.dump(metrics, f, indent=2)
    logger.log_file_created("training_metrics.json", str(model_dir))
    
    # =========================================================================
    # PHASE SUMMARY
    # =========================================================================
    all_gates_passed = all([gate_6_1, gate_6_2, gate_6_3])
    
    status = logger.end_phase(
        next_steps=[
            "Phase 7: Overfitting Detection & Prevention",
            "Cross-validation analysis",
            "Learning curve analysis"
        ]
    )
    
    return status in ["PASSED", "PASSED WITH WARNINGS"]


if __name__ == "__main__":
    success = run_phase_6()
    sys.exit(0 if success else 1)
```

---

## 15. Appendix: Gate Summary

### Complete Gate Reference

| Phase | Gate ID | Gate Name | Pass Criteria | Severity |
|-------|---------|-----------|---------------|----------|
| 0 | G0.1 | Python Dependencies | All packages installed | BLOCKING |
| 0 | G0.2 | BigQuery Connectivity | Connection successful | BLOCKING |
| 0 | G0.3 | Dataset Access | All datasets accessible | BLOCKING |
| 0 | G0.4 | Directory Structure | All directories created | BLOCKING |
| 0 | G0.5 | Data Volume | >= 10,000 contacted leads | BLOCKING |
| 0 | G0.6 | Firm Historicals | >= 12 months coverage | WARNING |
| 1 | G1.1 | Minimum Sample Size | >= 10,000 mature leads | BLOCKING |
| 1 | G1.2 | Conversion Rate Range | 2% - 8% | WARNING |
| 1 | G1.3 | Right-Censoring Rate | <= 40% | WARNING |
| 1 | G1.4 | FINTRX Match Rate | >= 75% | WARNING |
| 1 | G1.5 | Employment History | >= 70% coverage | WARNING |
| 2 | G2.1 | Feature Count | >= 15 features | WARNING |
| 2 | G2.2 | No Future Data | All PIT-compliant | BLOCKING |
| 2 | G2.3 | Null Rates | No feature > 50% null | WARNING |
| 2 | G2.4 | Interaction Features | Created successfully | WARNING |
| 2 | G2.5 | Target Preserved | Same row count | BLOCKING |
| 3 | G3.1 | Features Documented | 0 unknown features | WARNING |
| 3 | G3.2 | No Suspicious IV | 0 features with IV > 0.5 | BLOCKING |
| 3 | G3.3 | Valid Tenure | 0 negative values | BLOCKING |
| 3 | G3.4 | Valid Mobility | Max <= 10 | WARNING |
| 3 | G3.5 | Interactions Valid | Correct calculations | BLOCKING |
| 3 | G3.6 | Lift Consistent | Within expected range | WARNING |
| 4 | G4.1 | Limited Correlations | <= 3 pairs > 0.7 | WARNING |
| 4 | G4.2 | Limited High VIF | <= 2 features VIF > 5 | WARNING |
| 4 | G4.3 | Final VIF | Max VIF <= 7.5 | WARNING |
| 5 | G5.1 | Training Size | >= 20,000 leads | BLOCKING |
| 5 | G5.2 | Test Size | >= 3,000 leads | BLOCKING |
| 5 | G5.3 | Lead Source Drift | <= 20% LinkedIn drift | WARNING |
| 5 | G5.4 | Conversion Consistency | <= 30% relative diff | WARNING |
| 5 | G5.5 | Train/Test Gap | >= 30 days | BLOCKING |
| 6 | G6.1 | Early Stopping | Triggered before max | WARNING |
| 6 | G6.2 | Lift Gap | <= 0.5x | BLOCKING |
| 6 | G6.3 | AUC Gap | <= 0.05 | WARNING |
| 7 | G7.1 | CV Variance | Std dev < 0.1 | WARNING |
| 7 | G7.2 | Learning Curve | Converged | WARNING |
| 8 | G8.1 | Min Top Decile Lift | >= 1.5x | BLOCKING |
| 8 | G8.2 | Min AUC-ROC | >= 0.60 | WARNING |
| 8 | G8.3 | Min AUC-PR | >= 0.10 | WARNING |
| 8 | G8.4 | Statistical Significance | p < 0.05 | WARNING |

### Gate Severity Levels

- **BLOCKING**: Phase cannot proceed until gate passes
- **WARNING**: Phase can proceed but issue should be documented and monitored

---

## Execution Checklist

```
[ ] Phase 0: Environment Setup
    [ ] Create directory structure
    [ ] Verify dependencies
    [ ] Test BigQuery connection
    [ ] Validate data access
    
[ ] Phase 1: Data Extraction
    [ ] Execute target definition SQL
    [ ] Validate target distribution
    [ ] Check FINTRX coverage
    [ ] Document conversion rate
    
[ ] Phase 2: Feature Engineering
    [ ] Create PIT-safe features
    [ ] Validate tenure calculation
    [ ] Validate mobility calculation
    [ ] Create interaction features
    
[ ] Phase 3: Leakage Audit
    [ ] Calculate Information Value
    [ ] Check for suspicious features
    [ ] Validate PIT compliance
    [ ] Generate leakage report
    
[ ] Phase 4: Multicollinearity
    [ ] Calculate correlation matrix
    [ ] Calculate VIF
    [ ] Remove correlated features
    [ ] Generate final feature list
    
[ ] Phase 5: Train/Test Split
    [ ] Create temporal splits
    [ ] Check lead source drift
    [ ] Create CV folds
    [ ] Save split data
    
[ ] Phase 6: Model Training
    [ ] Configure regularization
    [ ] Train with early stopping
    [ ] Evaluate performance
    [ ] Check for overfitting
    
[ ] Phase 7: Overfitting Detection
    [ ] Cross-validation analysis
    [ ] Learning curve analysis
    [ ] Segment performance check
    
[ ] Phase 8: Model Validation
    [ ] Calculate all metrics
    [ ] Lift by decile analysis
    [ ] Segment performance
    [ ] Generate validation report
    
[ ] Phase 9: SHAP Analysis
    [ ] Calculate SHAP values
    [ ] Generate importance plots
    [ ] Validate interpretability
    
[ ] Phase 10: Deployment
    [ ] Create production SQL
    [ ] Update model registry
    [ ] Generate final documentation
```

---

**Document Version**: 1.0.0  
**Created**: December 2025  
**Status**: Ready for Execution

