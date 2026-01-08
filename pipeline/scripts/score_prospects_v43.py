"""
V4.3.1 Prospect Scoring Script with Gain-Based Narratives

Changes from V4.3.0:
- Added is_likely_recent_promotee feature (26 total features)
- Career Clock data now uses corrected employment history (excludes current firm)

Changes from V4.2.0:
- Added Career Clock features (cc_is_in_move_window, cc_is_too_early)
- Uses gain-based feature importance for narratives (same as V4.2.0)
- Note: SHAP base_score parsing bug deferred to V4.4.0 (XGBoost/SHAP compatibility issue)

Author: Lead Scoring Team
Date: 2026-01-08
"""

import pandas as pd
import numpy as np
import xgboost as xgb
import json
from pathlib import Path
from google.cloud import bigquery
from datetime import datetime

# Feature columns (must match training - same order as train_model_v43.py)
FEATURE_COLUMNS_V43 = [
    # Original V4 features (12)
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
    # Encoded categoricals (3)
    'tenure_bucket_encoded',
    'mobility_tier_encoded',
    'firm_stability_tier_encoded',
    # V4.1 Bleeding features (4)
    'is_recent_mover',
    'days_since_last_move',
    'firm_departures_corrected',
    'bleeding_velocity_encoded',
    # V4.1 Firm/Rep type features (3)
    'is_independent_ria',
    'is_ia_rep_type',
    'is_dual_registered',
    # V4.2.0 NEW: Age feature (1)
    'age_bucket_encoded',
    # V4.3.0: Career Clock features (2)
    'cc_is_in_move_window',
    'cc_is_too_early',
    # V4.3.1: Recent promotee feature (1) - NEW
    'is_likely_recent_promotee',
]

# Human-readable feature descriptions
FEATURE_DESCRIPTIONS = {
    'cc_is_in_move_window': {
        'positive': '⏰ Career Clock: In personal move window (optimal timing)',
        'negative': 'Career Clock: Not in move window',
    },
    'cc_is_too_early': {
        'positive': '🌱 Career Clock: Too early in cycle (lower priority)',
        'negative': 'Career Clock: Not too early',
    },
    'is_likely_recent_promotee': {
        'positive': '⚠️ Recent promotee pattern (<5yr tenure + senior title)',
        'negative': 'Established tenure for title level',
    },
    'age_bucket_encoded': {
        'positive': 'Age group increases conversion likelihood',
        'negative': 'Age group decreases conversion likelihood',
    },
    'firm_net_change_12mo': {
        'positive': 'Firm instability (bleeding firm signal)',
        'negative': 'Firm stability (growing or stable)',
    },
    'is_independent_ria': {
        'positive': 'Independent RIA (portable book)',
        'negative': 'Not independent RIA',
    },
    'is_dual_registered': {
        'positive': 'Dual-registered (flexible transition)',
        'negative': 'Not dual-registered',
    },
    'mobility_3yr': {
        'positive': 'Recent mobility history',
        'negative': 'Low recent mobility',
    },
    'tenure_months': {
        'positive': 'Tenure pattern suggests readiness',
        'negative': 'Tenure pattern suggests stability',
    },
    'experience_years': {
        'positive': 'Experience level favorable',
        'negative': 'Experience level less favorable',
    },
    'firm_departures_corrected': {
        'positive': 'Firm experiencing departures',
        'negative': 'Firm not experiencing departures',
    },
    'bleeding_velocity_encoded': {
        'positive': 'Accelerating firm departures',
        'negative': 'Stable or decelerating departures',
    },
    'is_recent_mover': {
        'positive': 'Recently changed firms (proven mobility)',
        'negative': 'Not a recent mover',
    },
    'has_linkedin': {
        'positive': 'LinkedIn presence (contactable)',
        'negative': 'No LinkedIn profile',
    },
    'has_cfp': {
        'positive': 'CFP designation (book ownership signal)',
        'negative': 'No CFP designation',
    },
    'has_series_65_only': {
        'positive': 'Pure RIA (no BD ties, portable)',
        'negative': 'Has BD registration',
    },
    'is_wirehouse': {
        'positive': 'Wirehouse advisor',
        'negative': 'Not wirehouse',
    },
    'num_prior_firms': {
        'positive': 'Multiple prior firms (proven mover)',
        'negative': 'Few prior firms',
    },
}


def generate_gain_narrative(
    feature_values: pd.Series,
    feature_importance: dict,
    feature_names: list,
    top_n: int = 3
) -> dict:
    """
    Generate narrative from gain-based feature importance (same as V4.2.0).
    
    Args:
        feature_values: Feature values for one prospect
        feature_importance: Dictionary mapping feature names to importance scores
        feature_names: List of feature names (in model order)
        top_n: Number of top features to include
    
    Returns:
        Dictionary with narrative and top features
    """
    # Create feature-contribution pairs
    contributions = []
    for feat in feature_names:
        if feat not in feature_importance or feature_importance[feat] <= 0:
            continue
        
        value = feature_values.get(feat, 0)
        importance = feature_importance[feat]
        
        # Determine if this feature is notable for this lead
        is_notable = False
        direction = "positive"
        
        # Binary features
        if feat.startswith('is_') or feat.startswith('has_') or feat.startswith('cc_'):
            if value == 1:
                is_notable = True
                direction = "positive"
        # Encoded features
        elif '_encoded' in feat:
            if value >= 2:
                is_notable = True
                direction = "positive"
            elif value == 0 and importance > 0:
                is_notable = True
                direction = "negative"
        # Numeric features
        else:
            if feat == 'firm_net_change_12mo' and value < -3:
                is_notable = True
                direction = "positive"  # Bleeding firm is positive signal
            elif feat == 'mobility_3yr' and value >= 2:
                is_notable = True
                direction = "positive"
            elif feat == 'tenure_months' and value <= 24:
                is_notable = True
                direction = "positive"  # Short tenure is positive signal
            elif feat == 'experience_years' and value >= 10:
                is_notable = True
                direction = "positive"
            elif feat == 'firm_rep_count_at_contact' and value <= 10:
                is_notable = True
                direction = "positive"  # Small firm is positive signal
            elif feat == 'days_since_last_move' and value <= 365:
                is_notable = True
                direction = "positive"
            elif feat == 'firm_departures_corrected' and value >= 3:
                is_notable = True
                direction = "positive"
        
        if is_notable:
            contributions.append({
                'feature': feat,
                'value': float(value),
                'importance': float(importance),
                'direction': direction
            })
    
    # Sort by importance (most important notable features first)
    contributions.sort(key=lambda x: x['importance'], reverse=True)
    
    # Take top N notable features
    top_contributions = contributions[:top_n]
    
    # If we don't have enough notable features, pad with top importance features
    if len(top_contributions) < top_n:
        # Get top features by importance that aren't already included
        sorted_features = sorted(
            [(f, feature_importance.get(f, 0)) for f in feature_names],
            key=lambda x: x[1],
            reverse=True
        )
        for feat, imp in sorted_features:
            if imp <= 0:
                continue
            if any(c['feature'] == feat for c in top_contributions):
                continue
            value = feature_values.get(feat, 0)
            top_contributions.append({
                'feature': feat,
                'value': float(value),
                'importance': float(imp),
                'direction': "positive" if value > 0 else "negative"
            })
            if len(top_contributions) >= top_n:
                break
    
    # Generate narrative parts
    narrative_parts = []
    for contrib in top_contributions[:top_n]:
        feat = contrib['feature']
        direction = contrib['direction']
        
        if feat in FEATURE_DESCRIPTIONS:
            desc = FEATURE_DESCRIPTIONS[feat][direction]
            narrative_parts.append(desc)
        else:
            # Fallback for unmapped features
            direction_word = 'increases' if direction == 'positive' else 'decreases'
            narrative_parts.append(f"{feat.replace('_', ' ')} {direction_word} likelihood")
    
    return {
        'narrative': ". ".join(narrative_parts) if narrative_parts else "Standard lead profile",
        'top1_feature': top_contributions[0]['feature'] if len(top_contributions) > 0 else None,
        'top1_importance': round(top_contributions[0]['importance'], 4) if len(top_contributions) > 0 else None,
        'top1_direction': top_contributions[0]['direction'] if len(top_contributions) > 0 else None,
        'top2_feature': top_contributions[1]['feature'] if len(top_contributions) > 1 else None,
        'top2_importance': round(top_contributions[1]['importance'], 4) if len(top_contributions) > 1 else None,
        'top2_direction': top_contributions[1]['direction'] if len(top_contributions) > 1 else None,
        'top3_feature': top_contributions[2]['feature'] if len(top_contributions) > 2 else None,
        'top3_importance': round(top_contributions[2]['importance'], 4) if len(top_contributions) > 2 else None,
        'top3_direction': top_contributions[2]['direction'] if len(top_contributions) > 2 else None,
    }


def score_prospects_v43(
    model_dir: str = "v4/models/v4.3.1",
    features_table: str = "savvy-gtm-analytics.ml_features.v4_prospect_features",
    output_table: str = "savvy-gtm-analytics.ml_features.v4_prospect_scores",
    project_id: str = "savvy-gtm-analytics",
    batch_size: int = 10000
):
    """
    Score all prospects with V4.3.1 model and generate gain-based narratives.
    
    Note: Uses gain-based feature importance (same as V4.2.0) due to XGBoost/SHAP
    base_score parsing compatibility issue. SHAP fix deferred to V4.4.0.
    
    Args:
        model_dir: Directory containing V4.3.0 model artifacts
        features_table: BigQuery table with prospect features
        output_table: BigQuery table for scores output
        project_id: GCP project ID
        batch_size: Number of prospects to score per batch
    """
    
    print("=" * 70)
    print("V4.3.1 PROSPECT SCORING WITH GAIN-BASED NARRATIVES")
    print("=" * 70)
    
    model_path = Path(model_dir)
    
    # Load model
    print("\n[1/5] Loading V4.3.1 model...")
    model = xgb.XGBClassifier()
    model.load_model(str(model_path / "v4.3.1_model.json"))
    
    # Load feature importance (gain-based)
    print("[2/5] Loading feature importance...")
    importance_df = pd.read_csv(model_path / "v4.3.1_feature_importance.csv")
    feature_importance = dict(zip(importance_df['feature'], importance_df['gain_importance']))
    print(f"  Loaded importance for {len(feature_importance)} features")
    
    # Load prospect features
    print("\n[3/5] Loading prospect features...")
    client = bigquery.Client(project=project_id)
    
    query = f"""
    SELECT 
        crd,
        prediction_date,
        {', '.join(FEATURE_COLUMNS_V43)}
    FROM `{features_table}`
    """
    
    df = client.query(query).to_dataframe()
    print(f"  Loaded {len(df):,} prospects")
    
    # Score prospects
    print("\n[4/5] Scoring prospects and generating gain-based narratives...")
    
    X = df[FEATURE_COLUMNS_V43]
    
    # Get predictions
    predictions = model.predict_proba(X)[:, 1]
    print(f"  Scored {len(predictions):,} prospects")
    
    # Generate narratives using gain-based importance
    print("  Generating gain-based narratives...")
    narratives = []
    for i in range(len(df)):
        narrative_data = generate_gain_narrative(
            X.iloc[i],
            feature_importance,
            FEATURE_COLUMNS_V43,
            top_n=3
        )
        narratives.append(narrative_data)
    
    # Build output dataframe
    print("\n[5/5] Building output table...")
    
    output_df = pd.DataFrame({
        'crd': df['crd'],
        'prediction_date': df['prediction_date'],
        'v4_score': predictions,
        'v4_percentile': pd.qcut(predictions, 100, labels=False, duplicates='drop') + 1,
        
        # Career Clock features for transparency
        'cc_is_in_move_window': df['cc_is_in_move_window'],
        'cc_is_too_early': df['cc_is_too_early'],
        
        # Flags
        'v4_deprioritize': predictions < np.percentile(predictions, 20),
        'v4_upgrade_candidate': predictions >= np.percentile(predictions, 80),
        
        # Gain-based narratives (V4.3.0 uses gain-based, SHAP deferred to V4.4.0)
        'shap_top1_feature': [n['top1_feature'] for n in narratives],
        'shap_top1_value': [n['top1_importance'] for n in narratives],  # Using importance for gain-based
        'shap_top1_direction': [n['top1_direction'] for n in narratives],
        'shap_top2_feature': [n['top2_feature'] for n in narratives],
        'shap_top2_value': [n['top2_importance'] for n in narratives],  # Using importance for gain-based
        'shap_top2_direction': [n['top2_direction'] for n in narratives],
        'shap_top3_feature': [n['top3_feature'] for n in narratives],
        'shap_top3_value': [n['top3_importance'] for n in narratives],  # Using importance for gain-based
        'shap_top3_direction': [n['top3_direction'] for n in narratives],
        'v4_narrative': [n['narrative'] for n in narratives],
        
        # Metadata
        'model_version': 'V4.3.1',
        'narrative_method': 'gain-based',  # Note: SHAP deferred to V4.4.0
        'scored_at': datetime.now(),
    })
    
    # Upload to BigQuery
    print(f"  Uploading {len(output_df):,} scores to BigQuery...")
    
    job_config = bigquery.LoadJobConfig(
        write_disposition='WRITE_TRUNCATE',
        schema=[
            bigquery.SchemaField('crd', 'INTEGER'),
            bigquery.SchemaField('prediction_date', 'DATE'),
            bigquery.SchemaField('v4_score', 'FLOAT'),
            bigquery.SchemaField('v4_percentile', 'INTEGER'),
            bigquery.SchemaField('cc_is_in_move_window', 'INTEGER'),
            bigquery.SchemaField('cc_is_too_early', 'INTEGER'),
            bigquery.SchemaField('v4_deprioritize', 'BOOLEAN'),
            bigquery.SchemaField('v4_upgrade_candidate', 'BOOLEAN'),
            bigquery.SchemaField('shap_top1_feature', 'STRING'),
            bigquery.SchemaField('shap_top1_value', 'FLOAT'),
            bigquery.SchemaField('shap_top1_direction', 'STRING'),
            bigquery.SchemaField('shap_top2_feature', 'STRING'),
            bigquery.SchemaField('shap_top2_value', 'FLOAT'),
            bigquery.SchemaField('shap_top2_direction', 'STRING'),
            bigquery.SchemaField('shap_top3_feature', 'STRING'),
            bigquery.SchemaField('shap_top3_value', 'FLOAT'),
            bigquery.SchemaField('shap_top3_direction', 'STRING'),
            bigquery.SchemaField('v4_narrative', 'STRING'),
            bigquery.SchemaField('model_version', 'STRING'),
            bigquery.SchemaField('narrative_method', 'STRING'),
            bigquery.SchemaField('scored_at', 'TIMESTAMP'),
        ]
    )
    
    job = client.load_table_from_dataframe(output_df, output_table, job_config=job_config)
    job.result()
    
    print(f"\n  [OK] Scoring complete!")
    print(f"  Output table: {output_table}")
    print(f"  Total prospects scored: {len(output_df):,}")
    
    # Summary stats
    print(f"\n  Score Distribution:")
    print(f"    Mean score: {predictions.mean():.4f}")
    print(f"    Median score: {np.median(predictions):.4f}")
    print(f"    Top 10% threshold: {np.percentile(predictions, 90):.4f}")
    print(f"    Bottom 20% threshold: {np.percentile(predictions, 20):.4f}")
    
    print(f"\n  Career Clock Distribution:")
    print(f"    In Move Window: {(df['cc_is_in_move_window'] == 1).sum():,} ({(df['cc_is_in_move_window'] == 1).mean()*100:.1f}%)")
    print(f"    Too Early: {(df['cc_is_too_early'] == 1).sum():,} ({(df['cc_is_too_early'] == 1).mean()*100:.1f}%)")


if __name__ == "__main__":
    import argparse
    
    # Get script directory and construct default model path relative to project root
    script_dir = Path(__file__).parent  # pipeline/scripts/
    project_root = script_dir.parent.parent  # project root
    default_model_dir = project_root / "v4" / "models" / "v4.3.1"
    
    parser = argparse.ArgumentParser(description='Score prospects with V4.3.1 model')
    parser.add_argument('--model-dir', default=str(default_model_dir))
    parser.add_argument('--features-table', default='savvy-gtm-analytics.ml_features.v4_prospect_features')
    parser.add_argument('--output-table', default='savvy-gtm-analytics.ml_features.v4_prospect_scores')
    parser.add_argument('--project', default='savvy-gtm-analytics')
    
    args = parser.parse_args()
    
    score_prospects_v43(
        model_dir=args.model_dir,
        features_table=args.features_table,
        output_table=args.output_table,
        project_id=args.project
    )
