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
BASELINE_CONVERSION_RATE = 0.0254  # 2.54% (Provided Lead List only - outbound leads)

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
    MAX_DEPTH = 3  # Reduced from 4 to 3 for stronger regularization
    MIN_CHILD_WEIGHT = 50  # Increased from 10 to 50 for stronger regularization
    GAMMA = 0.1  # Minimum loss reduction for split
    SUBSAMPLE = 0.8  # Row subsampling
    COLSAMPLE_BYTREE = 0.8  # Column subsampling
    REG_ALPHA = 1.0  # Increased from 0.1 to 1.0 (10x stronger L1)
    REG_LAMBDA = 10.0  # Increased from 1.0 to 10.0 (10x stronger L2)
    
    # Training parameters
    N_ESTIMATORS = 300  # Reduced from 500 to 300
    LEARNING_RATE = 0.03  # Reduced from 0.05 to 0.03 (slower learning)
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

