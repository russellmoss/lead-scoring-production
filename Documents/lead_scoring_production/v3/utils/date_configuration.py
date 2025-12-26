# =============================================================================
# PHASE 0.0: DYNAMIC DATE CONFIGURATION (MANDATORY FIRST STEP)
# =============================================================================
"""
This module MUST execute first. All downstream phases import dates from here.
NEVER hardcode dates in other phases - always reference these variables.

Based on data assessment from December 21, 2025:
- Firm_historicals: Jan 2024 - Nov 2025 (23 months)
- Salesforce Leads: 56,982 total (18,337 in 2024, 38,645 in 2025)
- CRD Match Rate: 95.72%
"""

from datetime import datetime, timedelta
try:
    from dateutil.relativedelta import relativedelta
except ImportError:
    # Fallback if dateutil not available
    relativedelta = None

class DateConfiguration:
    """
    Central date configuration for the entire pipeline.
    All dates are calculated relative to execution date.
    
    Key Constraints (from data assessment):
    - Firm_historicals starts Jan 2024, so training floor is Feb 2024
    - Firm_historicals has ~1 month lag (Dec data not available in Dec)
    - 30-day maturity window required for conversion observation
    """
    
    def __init__(self, execution_date: datetime = None):
        """
        Initialize date configuration.
        
        Args:
            execution_date: Override for testing. Defaults to today.
        """
        if execution_date is None:
            execution_date = datetime.now()
        elif isinstance(execution_date, datetime):
            pass  # Already a datetime
        else:
            # Assume it's a date object, convert to datetime
            execution_date = datetime.combine(execution_date, datetime.min.time())
        
        self.execution_date = execution_date
        self._calculate_all_dates()
    
    def _calculate_all_dates(self):
        """Calculate all pipeline dates from execution date."""
        
        # FIRM_HISTORICALS_LAG: Firm data is typically 1 month behind
        # If we're in Dec 2025, latest firm data is Nov 2025
        self.firm_data_lag_months = 1
        
        # TRAINING_SNAPSHOT_DATE: End of last month with firm data
        first_of_current_month = self.execution_date.replace(day=1)
        last_month_end = first_of_current_month - timedelta(days=1)
        # Go back one more month for firm data lag
        self.training_snapshot_date = (last_month_end.replace(day=1) - timedelta(days=1))
        
        # Convert to date if datetime
        if isinstance(self.training_snapshot_date, datetime):
            self.training_snapshot_date = self.training_snapshot_date.date()
        
        # MATURITY_WINDOW: Days to wait for conversion outcome
        self.maturity_window_days = 30
        
        # TRAINING_END_DATE: Latest contacted_date we can use
        # Must be maturity_window before snapshot to observe outcomes
        training_end_dt = self.training_snapshot_date - timedelta(days=self.maturity_window_days)
        if isinstance(training_end_dt, datetime):
            self.training_end_date = training_end_dt.date()
        else:
            self.training_end_date = training_end_dt
        
        # TRAINING_START_DATE: Earliest contacted_date we can use
        # Firm_historicals starts Jan 2024, need Feb 2024 for prior month comparison
        self.training_start_date = datetime(2024, 2, 1).date()
        
        # Ensure training_end_date is a date object
        if isinstance(self.training_end_date, datetime):
            self.training_end_date = self.training_end_date.date()
        if isinstance(self.training_snapshot_date, datetime):
            self.training_snapshot_date = self.training_snapshot_date.date()
        
        # TEST_SPLIT_DATE: Where to split train vs test
        # Use approximately 80/20 split, with test being most recent 60 days
        total_days = (self.training_end_date - self.training_start_date).days
        test_days = min(60, int(total_days * 0.15))  # 15% or 60 days, whichever is smaller
        self.test_split_date = self.training_end_date - timedelta(days=test_days)
        if isinstance(self.test_split_date, datetime):
            self.test_split_date = self.test_split_date.date()
        
        # GAP_DAYS: Minimum gap between train and test to prevent leakage
        self.gap_days = 30
        
        # Adjusted train end (with gap before test)
        self.train_end_date = self.test_split_date - timedelta(days=self.gap_days)
        if isinstance(self.train_end_date, datetime):
            self.train_end_date = self.train_end_date.date()
        
        # TEST dates
        self.test_start_date = self.test_split_date
        self.test_end_date = self.training_end_date
        
        # LATEST_FIRM_SNAPSHOT: For scoring new leads without current month data
        self.latest_firm_snapshot_date = self.training_snapshot_date.replace(day=1)
    
    def validate(self):
        """Validate date configuration is sensible."""
        errors = []
        
        # Check we have enough training data
        train_days = (self.train_end_date - self.training_start_date).days
        if train_days < 180:
            errors.append(f"Insufficient training data: only {train_days} days (need 180+)")
        
        # Check we have enough test data
        test_days = (self.test_end_date - self.test_start_date).days
        if test_days < 30:
            errors.append(f"Insufficient test data: only {test_days} days (need 30+)")
        
        # Check dates are in correct order
        if self.training_start_date >= self.train_end_date:
            errors.append("training_start_date must be before train_end_date")
        
        if self.test_start_date >= self.test_end_date:
            errors.append("test_start_date must be before test_end_date")
        
        # Check snapshot isn't in the future
        execution_date_only = self.execution_date.date() if isinstance(self.execution_date, datetime) else self.execution_date
        if self.training_snapshot_date > execution_date_only:
            errors.append("training_snapshot_date cannot be in the future")
        
        # Check training start is after Firm_historicals start
        firm_data_start = datetime(2024, 1, 1).date()
        if self.training_start_date < firm_data_start:
            errors.append(f"training_start_date ({self.training_start_date}) is before Firm_historicals start ({firm_data_start})")
        
        if errors:
            raise ValueError("Date configuration validation failed:\n" + "\n".join(errors))
        
        return True
    
    def print_summary(self):
        """Print date configuration summary."""
        train_days = (self.train_end_date - self.training_start_date).days
        test_days = (self.test_end_date - self.test_start_date).days
        
        exec_date_str = self.execution_date.strftime('%Y-%m-%d') if isinstance(self.execution_date, datetime) else str(self.execution_date)
        
        print("\n" + "="*70)
        print("  DYNAMIC DATE CONFIGURATION (v3)")
        print("  Based on Data Assessment: Dec 21, 2025")
        print("="*70)
        print(f"  Execution Date:        {exec_date_str}")
        print(f"  Training Snapshot:     {self.training_snapshot_date.strftime('%Y-%m-%d')}")
        print(f"  Latest Firm Data:      {self.latest_firm_snapshot_date.strftime('%Y-%m-%d')}")
        print(f"  Maturity Window:       {self.maturity_window_days} days")
        print("-"*70)
        print("  DATA CONSTRAINTS (from assessment)")
        print("    Firm_historicals:     Jan 2024 - Nov 2025 (23 months)")
        print("    Firm data lag:        ~1 month")
        print("    Total leads:          56,982")
        print("    Total MQLs:           2,413")
        print("-"*70)
        print("  TRAINING DATA")
        print(f"    Start:                {self.training_start_date.strftime('%Y-%m-%d')}")
        print(f"    End:                  {self.train_end_date.strftime('%Y-%m-%d')}")
        print(f"    Days:                 {train_days}")
        print("-"*70)
        print(f"  GAP (Leakage Prevention): {self.gap_days} days")
        print("-"*70)
        print("  TEST DATA")
        print(f"    Start:                {self.test_start_date.strftime('%Y-%m-%d')}")
        print(f"    End:                  {self.test_end_date.strftime('%Y-%m-%d')}")
        print(f"    Days:                 {test_days}")
        print("="*70 + "\n")
    
    def to_dict(self):
        """Export configuration as dictionary for SQL templating."""
        exec_date_str = self.execution_date.strftime('%Y-%m-%d') if isinstance(self.execution_date, datetime) else str(self.execution_date)
        return {
            'execution_date': exec_date_str,
            'training_snapshot_date': self.training_snapshot_date.strftime('%Y-%m-%d'),
            'latest_firm_snapshot_date': self.latest_firm_snapshot_date.strftime('%Y-%m-%d'),
            'maturity_window_days': self.maturity_window_days,
            'training_start_date': self.training_start_date.strftime('%Y-%m-%d'),
            'training_end_date': self.training_end_date.strftime('%Y-%m-%d'),
            'train_end_date': self.train_end_date.strftime('%Y-%m-%d'),
            'test_split_date': self.test_split_date.strftime('%Y-%m-%d'),
            'test_start_date': self.test_start_date.strftime('%Y-%m-%d'),
            'test_end_date': self.test_end_date.strftime('%Y-%m-%d'),
            'gap_days': self.gap_days,
            'firm_data_lag_months': self.firm_data_lag_months
        }
    
    def get_sql_parameters(self):
        """Get parameters formatted for SQL queries."""
        d = self.to_dict()
        return {
            'TRAINING_START': d['training_start_date'],
            'TRAINING_END': d['training_end_date'],
            'TRAIN_END': d['train_end_date'],
            'TEST_START': d['test_start_date'],
            'TEST_END': d['test_end_date'],
            'SNAPSHOT_DATE': d['training_snapshot_date'],
            'MATURITY_DAYS': d['maturity_window_days']
        }


# Directory creation function
def create_directory_structure():
    """Create Version-3 directory structure."""
    import os
    from pathlib import Path
    
    BASE_DIR = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-3")
    
    DIRECTORIES = [
        BASE_DIR / "utils",
        BASE_DIR / "data" / "raw",
        BASE_DIR / "data" / "features",
        BASE_DIR / "data" / "scored",
        BASE_DIR / "models",
        BASE_DIR / "reports" / "shap",
        BASE_DIR / "notebooks",
        BASE_DIR / "sql",
        BASE_DIR / "inference",
    ]
    
    for directory in DIRECTORIES:
        directory.mkdir(parents=True, exist_ok=True)
        print(f"[OK] Created: {directory}")
    
    # Create __init__.py in utils
    init_file = BASE_DIR / "utils" / "__init__.py"
    if not init_file.exists():
        init_file.write_text("# Lead Scoring v3 Utilities\n")
    
    print(f"\n[DIR] Directory structure created at: {BASE_DIR}")
    return BASE_DIR


# VALIDATION GATE G0.0.1: Date Configuration
def run_phase_0_0():
    """
    Execute Phase 0.0: Dynamic Date Configuration with logging.
    """
    import sys
    import json
    from pathlib import Path
    
    # Step 1: Create directory structure
    BASE_DIR = create_directory_structure()
    
    # Step 2: Add Version-3 to path for imports
    sys.path.insert(0, str(BASE_DIR))
    
    # Step 3: Import logger (after directories exist)
    try:
        from utils.execution_logger import ExecutionLogger
        logger = ExecutionLogger()
        logger.start_phase("0.0", "Dynamic Date Configuration")
        logger.log_action("Created Version-3 directory structure")
        logger.log_file_created("Version-3/", str(BASE_DIR), "Base directory for model v3")
    except ImportError:
        # If logger doesn't exist yet, proceed without it
        print("[WARNING] ExecutionLogger not found. Proceeding without logger...")
        logger = None
    
    # Step 4: Create and validate date configuration
    if logger:
        logger.log_action("Calculating dynamic dates based on execution date")
    
    config = DateConfiguration()
    
    try:
        config.validate()
        if logger:
            logger.log_validation_gate("G0.0.1", "Date Configuration Valid", True, "All dates in correct order")
    except ValueError as e:
        if logger:
            logger.log_validation_gate("G0.0.1", "Date Configuration Valid", False, str(e))
            logger.end_phase(status="FAILED")
        raise
    
    # Step 5: Save configuration to Version-3 directory
    config_path = BASE_DIR / "date_config.json"
    with open(config_path, 'w') as f:
        json.dump(config.to_dict(), f, indent=2)
    
    if logger:
        logger.log_file_created("date_config.json", str(config_path), "Date configuration for all phases")
        
        # Log key metrics
        exec_date_str = config.execution_date.strftime('%Y-%m-%d') if isinstance(config.execution_date, datetime) else str(config.execution_date)
        logger.log_metric("Execution Date", exec_date_str)
        logger.log_metric("Training Start", config.training_start_date.strftime('%Y-%m-%d'))
        logger.log_metric("Training End", config.train_end_date.strftime('%Y-%m-%d'))
        logger.log_metric("Test Start", config.test_start_date.strftime('%Y-%m-%d'))
        logger.log_metric("Test End", config.test_end_date.strftime('%Y-%m-%d'))
        
        train_days = (config.train_end_date - config.training_start_date).days
        test_days = (config.test_end_date - config.test_start_date).days
        logger.log_metric("Training Days", train_days)
        logger.log_metric("Test Days", test_days)
        
        # Log learnings
        logger.log_learning(f"Training window covers {train_days} days ({train_days/30:.1f} months)")
        logger.log_learning(f"Firm data lag of {config.firm_data_lag_months} month(s) accounted for")
        
        # End phase
        logger.end_phase(
            status="PASSED",
            next_steps=[
                "Run Phase 0.0 pre-flight validation queries to verify data availability",
                "Proceed to Phase 0.1 Data Landscape Assessment"
            ]
        )
    
    config.print_summary()
    print(f"[OK] G0.0.1 PASSED: Date configuration validated and saved to {config_path}")
    return config


# Helper function to load config in other phases
def load_date_configuration():
    """Load date configuration from saved file."""
    import json
    from pathlib import Path
    
    config_path = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-3\date_config.json")
    with open(config_path, 'r') as f:
        config_dict = json.load(f)
    return config_dict


if __name__ == "__main__":
    config = run_phase_0_0()

