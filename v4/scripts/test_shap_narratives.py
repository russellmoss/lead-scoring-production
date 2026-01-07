"""
Test SHAP Narrative Generation for V4.2.0

Tests the TreeExplainer-based narrative generation on a sample lead.
"""

import pandas as pd
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from inference.lead_scorer_v4 import LeadScorerV4

def main():
    print("=" * 70)
    print("V4.2.0 SHAP Narrative Generation Test")
    print("=" * 70)
    
    # Initialize scorer
    print("\n[1/3] Initializing V4.2.0 scorer...")
    scorer = LeadScorerV4()
    
    # Sample lead features
    print("\n[2/3] Creating sample lead...")
    sample_lead = pd.DataFrame([{
        'tenure_months': 24,
        'mobility_3yr': 2,
        'firm_rep_count_at_contact': 15,
        'firm_net_change_12mo': -5,
        'is_wirehouse': 0,
        'is_broker_protocol': 1,
        'has_email': 1,
        'has_linkedin': 1,
        'has_firm_data': 1,
        'mobility_x_heavy_bleeding': 1,
        'short_tenure_x_high_mobility': 1,
        'experience_years': 12,
        'tenure_bucket_encoded': 1,
        'mobility_tier_encoded': 2,
        'firm_stability_tier_encoded': 2,
        'is_recent_mover': 1,
        'days_since_last_move': 180,
        'firm_departures_corrected': 5,
        'bleeding_velocity_encoded': 2,
        'is_independent_ria': 1,
        'is_ia_rep_type': 0,
        'is_dual_registered': 0,
        'age_bucket_encoded': 1  # 35-49
    }])
    
    # Generate narrative
    print("\n[3/3] Generating SHAP narrative...")
    try:
        result = scorer.get_shap_narrative(sample_lead)
        
        print("\n" + "=" * 70)
        print("Sample Lead Narrative:")
        print("=" * 70)
        print(f"  V4 Score: {scorer.score_leads(sample_lead)[0]:.4f}")
        print(f"\n  Top 1 Feature: {result['shap_top1_feature']}")
        print(f"    SHAP Value: {result['shap_top1_value']:+.4f}")
        print(f"\n  Top 2 Feature: {result['shap_top2_feature']}")
        print(f"    SHAP Value: {result['shap_top2_value']:+.4f}")
        print(f"\n  Top 3 Feature: {result['shap_top3_feature']}")
        print(f"    SHAP Value: {result['shap_top3_value']:+.4f}")
        print(f"\n  Narrative: {result['v4_narrative']}")
        print("=" * 70)
        
        print("\n✅ SHAP narrative generation successful!")
        
    except Exception as e:
        print(f"\nError generating narrative: {e}")
        import traceback
        traceback.print_exc()
        return False
    
    # Test batch processing
    print("\n" + "=" * 70)
    print("Testing Batch Processing (3 leads)...")
    print("=" * 70)
    
    batch_leads = pd.DataFrame([
        {
            'tenure_months': 24, 'mobility_3yr': 2, 'firm_rep_count_at_contact': 15,
            'firm_net_change_12mo': -5, 'is_wirehouse': 0, 'is_broker_protocol': 1,
            'has_email': 1, 'has_linkedin': 1, 'has_firm_data': 1,
            'mobility_x_heavy_bleeding': 1, 'short_tenure_x_high_mobility': 1,
            'experience_years': 12, 'tenure_bucket_encoded': 1, 'mobility_tier_encoded': 2,
            'firm_stability_tier_encoded': 2, 'is_recent_mover': 1, 'days_since_last_move': 180,
            'firm_departures_corrected': 5, 'bleeding_velocity_encoded': 2,
            'is_independent_ria': 1, 'is_ia_rep_type': 0, 'is_dual_registered': 0,
            'age_bucket_encoded': 1
        },
        {
            'tenure_months': 60, 'mobility_3yr': 0, 'firm_rep_count_at_contact': 50,
            'firm_net_change_12mo': 10, 'is_wirehouse': 1, 'is_broker_protocol': 1,
            'has_email': 1, 'has_linkedin': 1, 'has_firm_data': 1,
            'mobility_x_heavy_bleeding': 0, 'short_tenure_x_high_mobility': 0,
            'experience_years': 20, 'tenure_bucket_encoded': 3, 'mobility_tier_encoded': 0,
            'firm_stability_tier_encoded': 4, 'is_recent_mover': 0, 'days_since_last_move': 9999,
            'firm_departures_corrected': 0, 'bleeding_velocity_encoded': 0,
            'is_independent_ria': 0, 'is_ia_rep_type': 0, 'is_dual_registered': 1,
            'age_bucket_encoded': 2
        },
        {
            'tenure_months': 6, 'mobility_3yr': 3, 'firm_rep_count_at_contact': 8,
            'firm_net_change_12mo': -15, 'is_wirehouse': 0, 'is_broker_protocol': 0,
            'has_email': 0, 'has_linkedin': 0, 'has_firm_data': 1,
            'mobility_x_heavy_bleeding': 1, 'short_tenure_x_high_mobility': 1,
            'experience_years': 5, 'tenure_bucket_encoded': 0, 'mobility_tier_encoded': 2,
            'firm_stability_tier_encoded': 1, 'is_recent_mover': 1, 'days_since_last_move': 30,
            'firm_departures_corrected': 8, 'bleeding_velocity_encoded': 3,
            'is_independent_ria': 1, 'is_ia_rep_type': 1, 'is_dual_registered': 0,
            'age_bucket_encoded': 0
        }
    ])
    
    try:
        batch_results = scorer.score_leads_with_narratives(batch_leads)
        print(f"\n✅ Processed {len(batch_results)} leads successfully!")
        print("\nBatch Results:")
        print(batch_results[['v4_score', 'shap_top1_feature', 'v4_narrative']].to_string(index=False))
        
    except Exception as e:
        print(f"\n❌ Error in batch processing: {e}")
        import traceback
        traceback.print_exc()
        return False
    
    print("\n" + "=" * 70)
    print("✅ All tests passed!")
    print("=" * 70)
    
    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
