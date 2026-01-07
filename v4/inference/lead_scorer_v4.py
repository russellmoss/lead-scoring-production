"""
V4.2.0 Lead Scorer with Gain-Based Narratives
=============================================
Uses XGBoost native feature importance (gain) instead of SHAP.
SHAP TreeExplainer has a known bug with base_score serialization.
See v4/SHAP_debug.md for details.

Version: V4.2.0 (Age Feature)
Features: 23 (22 from V4.1.0 + age_bucket_encoded)
Deployed: 2026-01-07
"""

import xgboost as xgb
import pandas as pd
import numpy as np
import pickle
import json
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Default paths
DEFAULT_MODEL_DIR = Path(__file__).parent.parent / "models" / "v4.2.0"
DEFAULT_FEATURES_FILE = Path(__file__).parent.parent / "data" / "v4.1.0_r3" / "final_features.json"

# V4.2.0 Feature list (23 features)
FEATURES_V42 = [
    'tenure_months',
    'mobility_3yr',
    'firm_rep_count_at_contact',
    'firm_net_change_12mo',
    'is_wirehouse',
    'is_broker_protocol',
    'has_email',
    'has_linkedin',
    'has_firm_data',
    'mobility_x_heavy_bleeding',
    'short_tenure_x_high_mobility',
    'experience_years',
    'tenure_bucket_encoded',
    'mobility_tier_encoded',
    'firm_stability_tier_encoded',
    'is_recent_mover',
    'days_since_last_move',
    'firm_departures_corrected',
    'bleeding_velocity_encoded',
    'is_independent_ria',
    'is_ia_rep_type',
    'is_dual_registered',
    'age_bucket_encoded'  # NEW in V4.2.0
]

# Human-readable feature names for narratives
FEATURE_LABELS = {
    'tenure_months': 'Tenure at Current Firm',
    'tenure_bucket_encoded': 'Tenure Category',
    'mobility_3yr': 'Recent Mobility',
    'mobility_tier_encoded': 'Mobility Tier',
    'firm_rep_count_at_contact': 'Firm Size',
    'firm_net_change_12mo': 'Firm Net Change',
    'firm_stability_tier_encoded': 'Firm Stability',
    'firm_departures_corrected': 'Firm Departures',
    'bleeding_velocity_encoded': 'Bleeding Velocity',
    'is_wirehouse': 'Wirehouse Flag',
    'is_broker_protocol': 'Broker Protocol',
    'is_independent_ria': 'Independent RIA',
    'is_ia_rep_type': 'IA Rep Type',
    'is_dual_registered': 'Dual Registered',
    'has_email': 'Has Email',
    'has_linkedin': 'Has LinkedIn',
    'has_firm_data': 'Has Firm Data',
    'experience_years': 'Industry Experience',
    'is_recent_mover': 'Recent Mover',
    'days_since_last_move': 'Days Since Last Move',
    'mobility_x_heavy_bleeding': 'Mobility × Bleeding',
    'short_tenure_x_high_mobility': 'Short Tenure × High Mobility',
    'age_bucket_encoded': 'Age Category'
}


class LeadScorerV4:
    """
    V4.2.0 Lead Scoring Model Interface with Gain-Based Narratives
    
    Uses XGBoost feature importance (gain) instead of SHAP for narratives.
    This avoids the base_score serialization bug that breaks SHAP TreeExplainer.
    
    Usage:
        scorer = LeadScorerV4()
        scores = scorer.score_leads(features_df)
        narrative = scorer.get_narrative(single_lead_df)
        batch_results = scorer.score_leads_with_narratives(features_df)
    """
    
    def __init__(self, model_dir: Path = None, features_file: Path = None):
        """
        Initialize the V4.2.0 lead scorer.
        
        Args:
            model_dir: Path to model directory (default: models/v4.2.0)
            features_file: Path to final_features.json (optional, uses V4.2.0 features by default)
        """
        self.model_dir = model_dir or DEFAULT_MODEL_DIR
        self.features_file = features_file or DEFAULT_FEATURES_FILE
        
        self.model = None
        self.feature_list = None
        self.feature_importance = None
        self.top_features = None
        
        # Load model and features
        self._load_model()
        self._load_features()
        self._load_feature_importance()
        self._load_calibrator()
        
        print(f"[INFO] V4.2.0 LeadScorer initialized")
        print(f"[INFO] Features: {len(self.feature_list)}")
        if self.top_features:
            print(f"[INFO] Top feature: {self.top_features[0][0]} (gain: {self.top_features[0][1]:.2f})")
    
    def _load_model(self):
        """Load model, preferring JSON format."""
        json_path = self.model_dir / "model.json"
        pkl_path = self.model_dir / "model.pkl"
        
        if json_path.exists():
            self.model = xgb.XGBClassifier()
            self.model.load_model(str(json_path))
            print(f"[INFO] Loaded model from {json_path} (JSON format)")
        elif pkl_path.exists():
            with open(pkl_path, 'rb') as f:
                self.model = pickle.load(f)
            print(f"[INFO] Loaded model from {pkl_path} (pickle format)")
        else:
            raise FileNotFoundError(f"Model file not found: {json_path} or {pkl_path}")
    
    def _load_features(self):
        """Load the final feature list from JSON or use V4.2.0 default."""
        # Always use V4.2.0 feature list (23 features including age_bucket_encoded)
        # The JSON file might be from V4.1.0 and missing age_bucket_encoded
        self.feature_list = FEATURES_V42.copy()
        
        print(f"[INFO] Loaded {len(self.feature_list)} features (V4.2.0)")
    
    def _load_feature_importance(self):
        """Load pre-computed feature importance or compute from model."""
        importance_path = self.model_dir / "feature_importance.csv"
        
        if importance_path.exists():
            df = pd.read_csv(importance_path)
            # Use 'importance' column if available, otherwise 'gain'
            importance_col = 'importance' if 'importance' in df.columns else 'gain'
            self.feature_importance = dict(zip(df['feature'], df[importance_col]))
            # Sort by importance
            sorted_features = sorted(
                self.feature_importance.items(), 
                key=lambda x: x[1], 
                reverse=True
            )
            self.top_features = sorted_features
            print(f"[INFO] Loaded feature importance from {importance_path}")
        else:
            # Compute from model using gain
            print("[INFO] Computing feature importance from model (gain)...")
            booster = self.model.get_booster()
            importance_dict = booster.get_score(importance_type='gain')
            
            # Map f0, f1, etc. to feature names
            self.feature_importance = {}
            for i, feat in enumerate(self.feature_list):
                # Try feature name first
                if feat in importance_dict:
                    self.feature_importance[feat] = importance_dict[feat]
                # Fall back to f0, f1, etc.
                elif f'f{i}' in importance_dict:
                    self.feature_importance[feat] = importance_dict[f'f{i}']
                else:
                    self.feature_importance[feat] = 0.0
            
            # Sort by importance
            sorted_features = sorted(
                self.feature_importance.items(), 
                key=lambda x: x[1], 
                reverse=True
            )
            self.top_features = sorted_features
            print(f"[INFO] Computed feature importance for {len(self.top_features)} features")
    
    def _load_calibrator(self):
        """Load isotonic calibrator if available (optional)."""
        calibrator_path = self.model_dir / "isotonic_calibrator.pkl"
        
        # Try current model_dir first
        if not calibrator_path.exists():
            # Fallback to v4.1.0_r3
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
        - Feature order matches training
        - Missing values are handled
        
        Args:
            df: DataFrame with lead features
            
        Returns:
            DataFrame with prepared features ready for model
        """
        X = df.copy()
        
        # Check for missing features
        missing_features = set(self.feature_list) - set(X.columns)
        if missing_features:
            raise ValueError(f"Missing required features: {missing_features}")
        
        # Select only the features we need, in the correct order
        X = X[self.feature_list].copy()
        
        # Fill missing values with 0 (conservative)
        X = X.fillna(0)
        
        return X
    
    def score_leads(self, X: pd.DataFrame) -> np.ndarray:
        """
        Score leads (returns probabilities).
        
        Args:
            X: DataFrame with lead features
            
        Returns:
            Array of scores (0-1 probabilities)
        """
        X_prep = self.prepare_features(X)
        scores = self.model.predict_proba(X_prep)[:, 1]
        
        # Apply calibrator if available
        if self.calibrator is not None:
            scores = self.calibrator.predict(scores.reshape(-1, 1)).flatten()
        
        return scores
    
    def get_percentiles(self, scores: np.ndarray) -> np.ndarray:
        """
        Calculate percentile ranks for scores.
        
        Args:
            scores: Array of scores
            
        Returns:
            Array of percentiles (1-100)
        """
        # Use empirical CDF for percentile calculation
        sorted_scores = np.sort(scores)
        percentiles = np.searchsorted(sorted_scores, scores) / len(scores) * 100
        return percentiles
    
    def get_deprioritize_flags(self, percentiles: np.ndarray, threshold: float = 20.0) -> np.ndarray:
        """
        Get deprioritize flags for bottom threshold% of leads.
        
        Args:
            percentiles: Array of percentiles
            threshold: Percentile threshold for deprioritization
            
        Returns:
            Boolean array (True = deprioritize)
        """
        return percentiles <= threshold
    
    def get_narrative(self, X_single: pd.DataFrame) -> Dict:
        """
        Generate narrative for a single lead based on feature values and importance.
        
        This uses gain-based importance instead of SHAP due to the base_score bug.
        The narrative highlights the top 3 features that:
        1. Have high importance globally
        2. Have notable values for this specific lead
        
        Args:
            X_single: DataFrame with features for a single lead (1 row)
            
        Returns:
            Dictionary with narrative and top features
        """
        # Prepare features
        X_prep = self.prepare_features(X_single)
        X_single_series = X_prep.iloc[0]
        
        # Score this lead
        score = self.score_leads(X_prep)[0]
        percentile = self.get_percentiles(np.array([score]))[0]
        
        # Find top contributing features for this lead
        # We look at features with high importance AND notable values
        contributions = []
        
        # Check top 15 most important features
        for feature, importance in self.top_features[:15]:
            if importance <= 0:
                continue
                
            value = X_single_series.get(feature, 0)
            
            # Determine if this feature is notable for this lead
            is_notable = False
            direction = "Up" if value > 0 else "Down"
            
            # Binary features
            if feature.startswith('is_') or feature.startswith('has_'):
                if value == 1:
                    is_notable = True
                    direction = "Yes"
            # Encoded features (higher = more signal)
            elif '_encoded' in feature:
                if value >= 2:  # Higher category
                    is_notable = True
                    direction = "High"
                elif value == 0 and importance > 0:
                    is_notable = True
                    direction = "Low"
            # Numeric features - check for notable values
            else:
                if feature == 'firm_net_change_12mo' and value < -3:
                    is_notable = True
                    direction = "Down (bleeding)"
                elif feature == 'mobility_3yr' and value >= 2:
                    is_notable = True
                    direction = "Up (mobile)"
                elif feature == 'tenure_months' and value <= 24:
                    is_notable = True
                    direction = "Down (short)"
                elif feature == 'experience_years' and value >= 10:
                    is_notable = True
                    direction = "Up (experienced)"
                elif feature == 'firm_rep_count_at_contact' and value <= 10:
                    is_notable = True
                    direction = "Down (small firm)"
                elif feature == 'days_since_last_move' and value <= 365:
                    is_notable = True
                    direction = "Recent"
                elif feature == 'firm_departures_corrected' and value >= 3:
                    is_notable = True
                    direction = "Up (departures)"
            
            if is_notable:
                label = FEATURE_LABELS.get(feature, feature.replace('_', ' ').title())
                contributions.append({
                    'feature': feature,
                    'label': label,
                    'value': float(value),
                    'importance': float(importance),
                    'direction': direction
                })
        
        # Sort by importance (most important notable features first)
        contributions.sort(key=lambda x: x['importance'], reverse=True)
        
        # Take top 3 notable features
        top3 = contributions[:3]
        
        # If we don't have 3 notable features, pad with top importance features
        while len(top3) < 3 and len(self.top_features) > len(top3):
            for feature, importance in self.top_features:
                if importance <= 0:
                    continue
                if feature not in [t['feature'] for t in top3]:
                    label = FEATURE_LABELS.get(feature, feature.replace('_', ' ').title())
                    value = X_single_series.get(feature, 0)
                    top3.append({
                        'feature': feature,
                        'label': label,
                        'value': float(value),
                        'importance': float(importance),
                        'direction': "-"
                    })
                    break
            if len(top3) >= 3:
                break
        
        # Build narrative
        if len(top3) >= 3:
            narrative = f"Key factors: {top3[0]['label']} ({top3[0]['direction']}), {top3[1]['label']} ({top3[1]['direction']}), {top3[2]['label']} ({top3[2]['direction']})"
        elif len(top3) > 0:
            parts = [f"{t['label']} ({t['direction']})" for t in top3]
            narrative = f"Key factors: {', '.join(parts)}"
        else:
            narrative = "Standard lead profile"
        
        return {
            'v4_score': round(float(score), 4),
            'v4_percentile': round(float(percentile), 1),
            'top1_feature': top3[0]['feature'] if len(top3) > 0 else None,
            'top1_label': top3[0]['label'] if len(top3) > 0 else None,
            'top1_value': top3[0]['value'] if len(top3) > 0 else None,
            'top2_feature': top3[1]['feature'] if len(top3) > 1 else None,
            'top2_label': top3[1]['label'] if len(top3) > 1 else None,
            'top2_value': top3[1]['value'] if len(top3) > 1 else None,
            'top3_feature': top3[2]['feature'] if len(top3) > 2 else None,
            'top3_label': top3[2]['label'] if len(top3) > 2 else None,
            'top3_value': top3[2]['value'] if len(top3) > 2 else None,
            'v4_narrative': narrative
        }
    
    def score_leads_with_narratives(self, X: pd.DataFrame) -> pd.DataFrame:
        """
        Score multiple leads with narratives.
        
        Args:
            X: DataFrame with lead features
            
        Returns:
            DataFrame with scores and narratives
        """
        X_prep = self.prepare_features(X)
        scores = self.score_leads(X_prep)
        percentiles = self.get_percentiles(scores)
        
        results = []
        for i in range(len(X_prep)):
            row = X_prep.iloc[i:i+1]  # Keep as DataFrame for get_narrative
            narrative_data = self.get_narrative(row)
            narrative_data['v4_score'] = round(float(scores[i]), 4)
            narrative_data['v4_percentile'] = round(float(percentiles[i]), 1)
            results.append(narrative_data)
        
        return pd.DataFrame(results)
    
    def get_feature_importance(self) -> pd.DataFrame:
        """
        Get feature importance from the model.
        
        Returns:
            DataFrame with feature names and importance scores
        """
        if self.top_features:
            return pd.DataFrame({
                'feature': [f[0] for f in self.top_features],
                'importance': [f[1] for f in self.top_features]
            })
        else:
            return pd.DataFrame()
