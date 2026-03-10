"""
Verify Salesforce Fields for V4.1.0

This script verifies that required Salesforce fields exist for V4.1.0 scoring.

REQUIREMENTS:
- simple-salesforce package: pip install simple-salesforce
- Salesforce credentials

USAGE:
    python v4/scripts/v4.1/verify_salesforce_fields.py
"""

import sys
from pathlib import Path

# Add project to path
WORKING_DIR = Path(__file__).parent.parent.parent
sys.path.insert(0, str(WORKING_DIR))

# Required Salesforce fields for V4.1.0
REQUIRED_FIELDS = {
    'V4_Score__c': {
        'type': 'Number',
        'precision': 18,
        'scale': 2,
        'description': 'Raw V4.1.0 prediction (0-1)'
    },
    'V4_Score_Percentile__c': {
        'type': 'Number',
        'precision': 18,
        'scale': 0,
        'description': 'V4.1.0 percentile rank (1-100)'
    },
    'V4_Deprioritize__c': {
        'type': 'Checkbox',
        'description': 'TRUE if bottom 20% (percentile <= 20)'
    },
    'V4_Model_Version__c': {
        'type': 'Text',
        'length': 50,
        'description': 'Model version (e.g., v4.1.0)'
    },
    'V4_Scored_At__c': {
        'type': 'DateTime',
        'description': 'Timestamp of V4.1.0 scoring'
    }
}

def verify_fields():
    """Verify Salesforce fields exist."""
    print("=" * 70)
    print("V4.1.0 SALESFORCE FIELD VERIFICATION")
    print("=" * 70)
    
    # Try to import simple-salesforce
    try:
        from simple_salesforce import Salesforce
    except ImportError:
        print("\n[ERROR] simple-salesforce not installed")
        print("   Install with: pip install simple-salesforce")
        print("\nMANUAL VERIFICATION CHECKLIST:")
        print("   Verify these fields exist in Salesforce Lead object:")
        for field_name, field_spec in REQUIRED_FIELDS.items():
            print(f"\n   Field: {field_name}")
            print(f"   Type: {field_spec['type']}")
            if 'precision' in field_spec:
                print(f"   Precision: {field_spec['precision']}")
            if 'scale' in field_spec:
                print(f"   Scale: {field_spec['scale']}")
            if 'length' in field_spec:
                print(f"   Length: {field_spec['length']}")
            print(f"   Description: {field_spec['description']}")
        return
    
    # Check if credentials are available
    import os
    sf_username = os.getenv('SALESFORCE_USERNAME')
    sf_password = os.getenv('SALESFORCE_PASSWORD')
    sf_token = os.getenv('SALESFORCE_SECURITY_TOKEN')
    
    if not all([sf_username, sf_password, sf_token]):
        print("\n[WARNING] Salesforce credentials not found in environment variables")
        print("   Set: SALESFORCE_USERNAME, SALESFORCE_PASSWORD, SALESFORCE_SECURITY_TOKEN")
        print("\nMANUAL VERIFICATION CHECKLIST:")
        print("   Verify these fields exist in Salesforce Lead object:")
        for field_name, field_spec in REQUIRED_FIELDS.items():
            print(f"\n   Field: {field_name}")
            print(f"   Type: {field_spec['type']}")
            if 'precision' in field_spec:
                print(f"   Precision: {field_spec['precision']}")
            if 'scale' in field_spec:
                print(f"   Scale: {field_spec['scale']}")
            if 'length' in field_spec:
                print(f"   Length: {field_spec['length']}")
            print(f"   Description: {field_spec['description']}")
        return
    
    # Connect to Salesforce
    print("\n[CONNECT] Connecting to Salesforce...")
    try:
        sf = Salesforce(
            username=sf_username,
            password=sf_password,
            security_token=sf_token
        )
        print("  [OK] Connected to Salesforce")
    except Exception as e:
        print(f"  [ERROR] Error connecting to Salesforce: {e}")
        return
    
    # Verify fields
    print("\n[VERIFY] Verifying Salesforce fields...")
    try:
        lead_desc = sf.Lead.describe()
        existing_fields = {field['name']: field for field in lead_desc['fields']}
        
        results = {}
        for field_name, field_spec in REQUIRED_FIELDS.items():
            if field_name in existing_fields:
                field = existing_fields[field_name]
                results[field_name] = {
                    'exists': True,
                    'type': field.get('type', 'Unknown'),
                    'label': field.get('label', 'Unknown')
                }
                print(f"  [OK] {field_name}: EXISTS ({field.get('type', 'Unknown')})")
            else:
                results[field_name] = {'exists': False}
                print(f"  [MISSING] {field_name}: MISSING")
                print(f"     Required: {field_spec['type']}")
                if 'precision' in field_spec:
                    print(f"     Precision: {field_spec['precision']}")
                if 'scale' in field_spec:
                    print(f"     Scale: {field_spec['scale']}")
        
        # Summary
        print("\n" + "=" * 70)
        existing_count = sum(1 for r in results.values() if r['exists'])
        total_count = len(REQUIRED_FIELDS)
        
        if existing_count == total_count:
            print("[SUCCESS] ALL FIELDS EXIST - Ready for V4.1.0 sync")
        else:
            print(f"[WARNING] {existing_count}/{total_count} fields exist")
            print("   Create missing fields before running sync")
        
        print("=" * 70)
        
        return results
        
    except Exception as e:
        print(f"  [ERROR] Error verifying fields: {e}")
        import traceback
        traceback.print_exc()
        return None


if __name__ == "__main__":
    results = verify_fields()

