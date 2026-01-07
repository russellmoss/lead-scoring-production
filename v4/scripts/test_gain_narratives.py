"""
Test V4.2.0 Gain-Based Narratives
==================================
Tests the new gain-based narrative generation (replacing SHAP).
"""
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from v4.inference.lead_scorer_v4 import LeadScorerV4
import pandas as pd

def main():
    print("=" * 60)
    print("V4.2.0 Gain-Based Narrative Test")
    print("=" * 60)
    
    # Initialize scorer
    print("\n[1/3] Initializing V4.2.0 scorer...")
    scorer = LeadScorerV4()
    
    # Test lead 1: High-signal lead (recent mover, bleeding firm, mobile)
    print("\n[2/3] Creating test leads...")
    test_lead_1 = pd.DataFrame([{
        'tenure_months': 18,
        'mobility_3yr': 2,
        'firm_rep_count_at_contact': 8,
        'firm_net_change_12mo': -7,
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
        'firm_stability_tier_encoded': 1,
        'is_recent_mover': 1,
        'days_since_last_move': 180,
        'firm_departures_corrected': 5,
        'bleeding_velocity_encoded': 2,
        'is_independent_ria': 1,
        'is_ia_rep_type': 0,
        'is_dual_registered': 0,
        'age_bucket_encoded': 1
    }])
    
    # Test lead 2: Low-signal lead (stable, wirehouse, no mobility)
    test_lead_2 = pd.DataFrame([{
        'tenure_months': 84,
        'mobility_3yr': 0,
        'firm_rep_count_at_contact': 500,
        'firm_net_change_12mo': 15,
        'is_wirehouse': 1,
        'is_broker_protocol': 1,
        'has_email': 1,
        'has_linkedin': 1,
        'has_firm_data': 1,
        'mobility_x_heavy_bleeding': 0,
        'short_tenure_x_high_mobility': 0,
        'experience_years': 20,
        'tenure_bucket_encoded': 3,
        'mobility_tier_encoded': 0,
        'firm_stability_tier_encoded': 4,
        'is_recent_mover': 0,
        'days_since_last_move': 9999,
        'firm_departures_corrected': 0,
        'bleeding_velocity_encoded': 0,
        'is_independent_ria': 0,
        'is_ia_rep_type': 0,
        'is_dual_registered': 1,
        'age_bucket_encoded': 2
    }])
    
    # Test lead 3: Medium-signal lead
    test_lead_3 = pd.DataFrame([{
        'tenure_months': 36,
        'mobility_3yr': 1,
        'firm_rep_count_at_contact': 25,
        'firm_net_change_12mo': -2,
        'is_wirehouse': 0,
        'is_broker_protocol': 1,
        'has_email': 1,
        'has_linkedin': 1,
        'has_firm_data': 1,
        'mobility_x_heavy_bleeding': 0,
        'short_tenure_x_high_mobility': 0,
        'experience_years': 8,
        'tenure_bucket_encoded': 2,
        'mobility_tier_encoded': 1,
        'firm_stability_tier_encoded': 2,
        'is_recent_mover': 0,
        'days_since_last_move': 730,
        'firm_departures_corrected': 2,
        'bleeding_velocity_encoded': 1,
        'is_independent_ria': 1,
        'is_ia_rep_type': 0,
        'is_dual_registered': 0,
        'age_bucket_encoded': 1
    }])
    
    # Test individual narratives
    print("\n[3/3] Testing narratives...")
    print("\n" + "=" * 60)
    print("Test Lead 1: High-Signal Lead")
    print("=" * 60)
    result1 = scorer.get_narrative(test_lead_1)
    print(f"Score: {result1['v4_score']:.4f} (Percentile: {result1['v4_percentile']:.1f})")
    print(f"Narrative: {result1['v4_narrative']}")
    if result1['top1_label']:
        print(f"Top 1: {result1['top1_label']} = {result1['top1_value']} ({result1.get('top1_feature', 'N/A')})")
    if result1['top2_label']:
        print(f"Top 2: {result1['top2_label']} = {result1['top2_value']} ({result1.get('top2_feature', 'N/A')})")
    if result1['top3_label']:
        print(f"Top 3: {result1['top3_label']} = {result1['top3_value']} ({result1.get('top3_feature', 'N/A')})")
    
    print("\n" + "=" * 60)
    print("Test Lead 2: Low-Signal Lead")
    print("=" * 60)
    result2 = scorer.get_narrative(test_lead_2)
    print(f"Score: {result2['v4_score']:.4f} (Percentile: {result2['v4_percentile']:.1f})")
    print(f"Narrative: {result2['v4_narrative']}")
    if result2['top1_label']:
        print(f"Top 1: {result2['top1_label']} = {result2['top1_value']} ({result2.get('top1_feature', 'N/A')})")
    if result2['top2_label']:
        print(f"Top 2: {result2['top2_label']} = {result2['top2_value']} ({result2.get('top2_feature', 'N/A')})")
    if result2['top3_label']:
        print(f"Top 3: {result2['top3_label']} = {result2['top3_value']} ({result2.get('top3_feature', 'N/A')})")
    
    print("\n" + "=" * 60)
    print("Test Lead 3: Medium-Signal Lead")
    print("=" * 60)
    result3 = scorer.get_narrative(test_lead_3)
    print(f"Score: {result3['v4_score']:.4f} (Percentile: {result3['v4_percentile']:.1f})")
    print(f"Narrative: {result3['v4_narrative']}")
    if result3['top1_label']:
        print(f"Top 1: {result3['top1_label']} = {result3['top1_value']} ({result3.get('top1_feature', 'N/A')})")
    if result3['top2_label']:
        print(f"Top 2: {result3['top2_label']} = {result3['top2_value']} ({result3.get('top2_feature', 'N/A')})")
    if result3['top3_label']:
        print(f"Top 3: {result3['top3_label']} = {result3['top3_value']} ({result3.get('top3_feature', 'N/A')})")
    
    # Test batch processing
    print("\n" + "=" * 60)
    print("Batch Test (All 3 Leads)")
    print("=" * 60)
    batch = pd.concat([test_lead_1, test_lead_2, test_lead_3], ignore_index=True)
    batch_results = scorer.score_leads_with_narratives(batch)
    print(batch_results[['v4_score', 'v4_percentile', 'v4_narrative']].to_string(index=False))
    
    print("\n" + "=" * 60)
    print("Test Complete!")
    print("=" * 60)
    
    return True

if __name__ == "__main__":
    success = main()
