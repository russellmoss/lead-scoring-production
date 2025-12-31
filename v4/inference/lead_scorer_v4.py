"""
V4.1.0 Lead Scorer - Production Inference Class

This module provides a simple interface for scoring leads with the V4.1.0 XGBoost model.
Designed for production use in BigQuery/Salesforce integration.

Version: V4.1.0 R3
Features: 22 (reduced from 26 via feature selection)
Deployed: 2025-12-30
"""

import pickle
import json
import pandas as pd
import numpy as np
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import xgboost as xgb

# Default paths (can be overridden)
# Updated for V4.1.0 production deployment
DEFAULT_MODEL_DIR = Path(__file__).parent.parent / "models" / "v4.1.0"
DEFAULT_FEATURES_FILE = Path(__file__).parent.parent / "data" / "v4.1.0" / "final_features.json"


class LeadScorerV4:
    """
    V4 Lead Scoring Model Interface
    
    Usage:
        scorer = LeadScorerV4()
        scores = scorer.score_leads(features_df)
        percentiles = scorer.get_percentiles(scores)
        deprioritize_flags = scorer.get_deprioritize_flags(percentiles, threshold=20)
    """
    
    def __init__(self, model_dir: Path = None, features_file: Path = None):
        """
        Initialize the V4.1.0 lead scorer.
        
        Args:
            model_dir: Path to model directory (default: models/v4.1.0)
            features_file: Path to final_features.json (default: data/v4.1.0/final_features.json)
        """
        self.model_dir = model_dir or DEFAULT_MODEL_DIR
        self.features_file = features_file or DEFAULT_FEATURES_FILE
        
        self.model = None
        self.feature_list = None
        self.feature_importance = None
        
        # Load model and features
        self._load_model()
        self._load_features()
        self._load_feature_importance()
        self._load_calibrator()
    
    def _load_model(self):
        """Load the trained XGBoost model from pickle."""
        model_path = self.model_dir / "model.pkl"
        if not model_path.exists():
            raise FileNotFoundError(f"Model file not found: {model_path}")
        
        with open(model_path, 'rb') as f:
            self.model = pickle.load(f)
        
        print(f"[INFO] Loaded model from {model_path}")
    
    def _load_features(self):
        """Load the final feature list from JSON."""
        if not self.features_file.exists():
            raise FileNotFoundError(f"Features file not found: {self.features_file}")
        
        with open(self.features_file, 'r') as f:
            features_data = json.load(f)
        
        self.feature_list = features_data['final_features']
        print(f"[INFO] Loaded {len(self.feature_list)} features")
    
    def _load_feature_importance(self):
        """Load feature importance from CSV."""
        importance_path = self.model_dir / "feature_importance.csv"
        if importance_path.exists():
            self.feature_importance = pd.read_csv(importance_path)
            print(f"[INFO] Loaded feature importance from {importance_path}")
        else:
            print(f"[WARNING] Feature importance file not found: {importance_path}")
    
    def _load_calibrator(self):
        """Load isotonic calibrator if available."""
        # Try current model_dir first
        calibrator_path = self.model_dir / "isotonic_calibrator.pkl"
        
        # If not found and we're in v4.1.0, try v4.1.0_r3
        if not calibrator_path.exists() and "v4.1.0" in str(self.model_dir) and "r3" not in str(self.model_dir):
            alt_path = Path(__file__).parent.parent / "models" / "v4.1.0_r3" / "isotonic_calibrator.pkl"
            if alt_path.exists():
                calibrator_path = alt_path
        
        if calibrator_path.exists():
            with open(calibrator_path, 'rb') as f:
                self.calibrator = pickle.load(f)
            print(f"[INFO] Loaded calibrator from {calibrator_path}")
        else:
            self.calibrator = None
            print(f"[INFO] No calibrator found (optional)")
    
    def prepare_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Prepare features for model inference.
        
        Ensures:
        - All required features are present
        - Categorical features are encoded correctly
        - Feature order matches training
        - Missing values are handled
        
        Args:
            df: DataFrame with lead features (from BigQuery production view)
            
        Returns:
            DataFrame with prepared features ready for model
        """
        # Create a copy to avoid modifying original
        X = df.copy()
        
        # Check for missing features
        missing_features = set(self.feature_list) - set(X.columns)
        if missing_features:
            raise ValueError(f"Missing required features: {missing_features}")
        
        # Select only the features we need, in the correct order
        X = X[self.feature_list].copy()
        
        # Handle categorical features (convert to codes)
        categorical_features = []
        for feat in self.feature_list:
            if X[feat].dtype == 'object' or X[feat].dtype.name == 'category':
                categorical_features.append(feat)
        
        # Convert categoricals to codes (matching training)
        for feat in categorical_features:
            if feat in X.columns:
                # Convert to category and then to codes
                X[feat] = X[feat].astype('category').cat.codes
                # Replace -1 (missing) with 0 (or appropriate default)
                X[feat] = X[feat].replace(-1, 0)
        
        # Fill NaN values (shouldn't happen after categorical encoding, but safety check)
        X = X.fillna(0)
        
        # Ensure numeric types
        for col in X.columns:
            if X[col].dtype == 'object':
                # If still object after encoding, try to convert
                try:
                    X[col] = pd.to_numeric(X[col], errors='coerce').fillna(0)
                except:
                    pass
        
        return X
    
    def score_leads(self, df: pd.DataFrame) -> np.ndarray:
        """
        Score leads using the V4 model.
        
        Args:
            df: DataFrame with lead features (from BigQuery production view)
            
        Returns:
            Array of prediction scores (0-1, probability of conversion)
        """
        # Prepare features
        X = self.prepare_features(df)
        
        # Generate predictions using XGBoost DMatrix
        dtest = xgb.DMatrix(X)
        scores = self.model.predict(dtest)
        
        return scores
    
    def score_leads_calibrated(self, df: pd.DataFrame) -> np.ndarray:
        """
        Score leads and apply isotonic calibration.
        
        Returns calibrated scores if calibrator exists, otherwise raw scores.
        Calibrated scores guarantee monotonic percentile rankings.
        
        Args:
            df: DataFrame with required features
            
        Returns:
            np.ndarray of calibrated scores (0-1)
        """
        raw_scores = self.score_leads(df)
        
        if self.calibrator is not None:
            calibrated_scores = self.calibrator.transform(raw_scores)
            return calibrated_scores
        else:
            return raw_scores
    
    def get_percentiles(self, scores: np.ndarray) -> np.ndarray:
        """
        Calculate percentile ranks for scores.
        
        Args:
            scores: Array of prediction scores
            
        Returns:
            Array of percentiles (1-100, where 100 = highest score)
        """
        # Calculate percentile rank (1-100)
        # Higher score = higher percentile
        percentiles = pd.Series(scores).rank(pct=True, method='min') * 100
        return percentiles.values.astype(int)
    
    def get_deprioritize_flags(self, percentiles: np.ndarray, threshold: int = 20) -> np.ndarray:
        """
        Get deprioritization flags for leads.
        
        Args:
            percentiles: Array of percentile ranks (1-100)
            threshold: Percentile threshold for deprioritization (default: 20)
            
        Returns:
            Boolean array (True = deprioritize, False = keep)
        """
        return percentiles <= threshold
    
    def score_with_metadata(self, df: pd.DataFrame, 
                           deprioritize_threshold: int = 20) -> pd.DataFrame:
        """
        Score leads and return scores with metadata.
        
        Args:
            df: DataFrame with lead features
            deprioritize_threshold: Percentile threshold for deprioritization
            
        Returns:
            DataFrame with columns:
            - lead_id (if present in input)
            - v4_score: Raw prediction (0-1)
            - v4_percentile: Percentile rank (1-100)
            - v4_deprioritize: Boolean flag (True if bottom threshold%)
        """
        # Score leads
        scores = self.score_leads(df)
        
        # Calculate percentiles
        percentiles = self.get_percentiles(scores)
        
        # Get deprioritize flags
        deprioritize = self.get_deprioritize_flags(percentiles, deprioritize_threshold)
        
        # Build result DataFrame
        result = pd.DataFrame({
            'v4_score': scores,
            'v4_percentile': percentiles,
            'v4_deprioritize': deprioritize
        })
        
        # Add lead_id if present
        if 'lead_id' in df.columns:
            result['lead_id'] = df['lead_id'].values
        
        return result
    
    def get_feature_importance(self) -> pd.DataFrame:
        """
        Get feature importance from the model.
        
        Returns:
            DataFrame with feature names and importance scores
        """
        if self.feature_importance is not None:
            return self.feature_importance.copy()
        else:
            # Fallback: get from model directly
            try:
                importance_dict = self.model.get_booster().get_score(importance_type='weight')
                importance_df = pd.DataFrame({
                    'feature': list(importance_dict.keys()),
                    'importance': list(importance_dict.values())
                }).sort_values('importance', ascending=False)
                return importance_df
            except:
                return pd.DataFrame()


# Convenience function for quick scoring
def score_leads(df: pd.DataFrame, 
                model_dir: Path = None,
                features_file: Path = None,
                deprioritize_threshold: int = 20) -> pd.DataFrame:
    """
    Quick function to score leads.
    
    Args:
        df: DataFrame with lead features
        model_dir: Optional path to model directory
        features_file: Optional path to features file
        deprioritize_threshold: Percentile threshold for deprioritization
        
    Returns:
        DataFrame with scores and metadata
    """
    scorer = LeadScorerV4(model_dir=model_dir, features_file=features_file)
    return scorer.score_with_metadata(df, deprioritize_threshold=deprioritize_threshold)


if __name__ == "__main__":
    # Example usage
    print("=" * 70)
    print("V4 LEAD SCORER - TEST")
    print("=" * 70)
    
    # Load test data
    test_path = Path(r"C:\Users\russe\Documents\Lead Scoring\Version-4\data\splits\test.csv")
    if test_path.exists():
        test_df = pd.read_csv(test_path)
        
        # Initialize scorer
        scorer = LeadScorerV4()
        
        # Score leads
        results = scorer.score_with_metadata(test_df, deprioritize_threshold=20)
        
        print(f"\nScored {len(results)} leads")
        print(f"\nScore Statistics:")
        print(f"  Mean: {results['v4_score'].mean():.4f}")
        print(f"  Min: {results['v4_score'].min():.4f}")
        print(f"  Max: {results['v4_score'].max():.4f}")
        print(f"\nDeprioritization (bottom 20%):")
        print(f"  Leads to skip: {results['v4_deprioritize'].sum()}")
        print(f"  Percentage: {results['v4_deprioritize'].mean()*100:.1f}%")
        
        print("\n" + "=" * 70)
        print("Top 10 Features by Importance:")
        print("=" * 70)
        importance = scorer.get_feature_importance()
        print(importance.head(10).to_string(index=False))
    else:
        print(f"[ERROR] Test data not found: {test_path}")

